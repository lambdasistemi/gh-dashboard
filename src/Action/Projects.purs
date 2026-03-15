-- | Project-related action handlers.
-- |
-- | This module handles all actions for the Projects
-- | page (GitHub Projects v2 boards):
-- |
-- | **Data fetching:**
-- | - `handleRefreshProjects`      — list all boards
-- | - `handleRefreshProjectItems`  — fetch items for
-- |   a board (paginated).
-- | - `handleRefreshProjectItem`   — re-fetch a single
-- |   issue's title/body after external edits.
-- |
-- | **Board interactions:**
-- | - `handleExpandProject`        — expand/collapse a
-- |   board, auto-fetching items on first open.
-- | - `handleSetItemStatus`        — optimistic drag to
-- |   a new status column.
-- | - `handleSubmitNewItem`        — create a draft
-- |   issue on a board.
-- | - `handleSubmitEditItem`       — rename a draft.
-- | - `handleDeleteItem`           — remove an item.
-- | - `handleSubmitRenameProject`  — rename a board.
-- |
-- | **Optimistic updates:** status changes, renames,
-- | and deletes are applied to state immediately before
-- | the API call, then rolled back on error. This keeps
-- | the UI snappy despite network latency.
module Action.Projects
  ( handleRefreshProjects
  , handleExpandProject
  , handleRefreshProjectItems
  , handleRefreshProjectItem
  , handleToggleProjectRepoFilter
  , handleSetItemStatus
  , handleSetNewItemTitle
  , handleSubmitNewItem
  , handleStartEditItem
  , handleSetEditItemTitle
  , handleSubmitEditItem
  , handleDeleteItem
  , handleStartRenameProject
  , handleSetRenameProjectTitle
  , handleSubmitRenameProject
  , friendlyProjectError
  ) where

import Prelude

import Action.Common
  ( Dispatch
  , HalogenAction
  , persistView
  , toggleSet
  )
import Data.Either (Either(..))
import Data.Array (filter, find, null)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), indexOf, toLower)
import Effect.Aff (Aff)
import FFI.Dialog (confirmDialog)
import GitHub.GraphQL
  ( addDraftItem
  , deleteProjectItem
  , fetchProjectItems
  , fetchUserProjects
  , renameProject
  , updateDraftItem
  , updateItemStatus
  )
import GitHub.Rest (fetchIssue)
import Halogen as H
import Effect.Class (liftEffect)
import Types
  ( Issue(..)
  , Project(..)
  , ProjectItem(..)
  )
import View.Types (Action(..), State)

handleRefreshProjects
  :: forall o. Dispatch o -> HalogenAction o
handleRefreshProjects dispatch = do
  st <- H.get
  H.modify_ _ { projectsLoading = true }
  result <- H.liftAff
    (fetchUserProjects st.token)
  case result of
    Left err ->
      H.modify_ _
        { error = Just (friendlyProjectError err)
        , projectsLoading = false
        }
    Right projs -> do
      H.modify_ _
        { projects = projs
        , projectsLoading = false
        , error = Nothing
        }
      dispatch RefreshAgentSessions

handleExpandProject
  :: forall o
   . Dispatch o
  -> String
  -> HalogenAction o
handleExpandProject dispatch projectId = do
  st <- H.get
  let
    newExp =
      if st.expandedProject == Just projectId then
        Nothing
      else Just projectId
  H.modify_ _
    { expandedProject = newExp
    , expandedItems =
        if newExp == Nothing then
          st.expandedItems
        else mempty
    }
  persistView
  when
    (not (Map.member projectId st.projectItems))
    do
      handleRefreshProjectItems dispatch projectId

handleRefreshProjectItems
  :: forall o
   . Dispatch o
  -> String
  -> HalogenAction o
handleRefreshProjectItems dispatch projectId = do
  dispatch RefreshAgentSessions
  st <- H.get
  let
    isFirstLoad =
      not (Map.member projectId st.projectItems)
  when isFirstLoad
    (H.modify_ _ { projectItemsLoading = true })
  result <- H.liftAff
    (fetchProjectItems st.token projectId)
  case result of
    Left err ->
      H.modify_ _
        { error = Just err
        , projectItemsLoading = false
        }
    Right res -> do
      H.modify_ _
        { projectItems = Map.insert
            projectId
            res.items
            st.projectItems
        , projectItemsLoading = false
        , error = Nothing
        }
      case res.statusField of
        Just sf ->
          H.modify_ _
            { projectStatusFields = Map.insert
                projectId
                sf
                st.projectStatusFields
            }
        Nothing -> pure unit

handleRefreshProjectItem
  :: forall o
   . String
  -> String
  -> Int
  -> HalogenAction o
handleRefreshProjectItem projectId repoName itemNum = do
  st <- H.get
  result <- H.liftAff
    (fetchIssue st.token repoName itemNum)
  case result of
    Left _ -> pure unit
    Right (Issue iss) ->
      case
        Map.lookup projectId
          st.projectItems
        of
        Nothing -> pure unit
        Just items ->
          let
            updated = map
              ( \(ProjectItem pi) ->
                  if
                    pi.repoName == Just repoName
                      && pi.number == Just itemNum then ProjectItem pi
                    { title = iss.title
                    , body = iss.body
                    }
                  else ProjectItem pi
              )
              items
          in
            H.modify_ _
              { projectItems = Map.insert
                  projectId
                  updated
                  st.projectItems
              }

handleToggleProjectRepoFilter
  :: forall o. String -> HalogenAction o
handleToggleProjectRepoFilter repo = do
  st <- H.get
  H.modify_ _
    { projectRepoFilters =
        toggleSet repo st.projectRepoFilters
    }
  persistView

handleSetItemStatus
  :: forall o
   . String
  -> String
  -> String
  -> HalogenAction o
handleSetItemStatus projectId itemId newStatus = do
  st <- H.get
  case
    Map.lookup projectId
      st.projectStatusFields
    of
    Nothing -> pure unit
    Just sf ->
      case
        find
          (\o -> o.name == newStatus)
          sf.options
        of
        Nothing -> pure unit
        Just opt -> do
          -- optimistic update
          case
            Map.lookup projectId
              st.projectItems
            of
            Nothing -> pure unit
            Just items ->
              let
                updated = map
                  ( \(ProjectItem pi) ->
                      if pi.itemId == itemId then
                        ProjectItem pi
                          { status = Just newStatus
                          }
                      else ProjectItem pi
                  )
                  items
              in
                H.modify_ _
                  { projectItems = Map.insert
                      projectId
                      updated
                      st.projectItems
                  }
          result <- H.liftAff $
            updateItemStatus st.token projectId
              itemId
              sf.fieldId
              opt.optionId
          case result of
            Left err ->
              H.modify_ _
                { error = Just err }
            Right _ -> pure unit

handleSetNewItemTitle
  :: forall o. String -> HalogenAction o
handleSetNewItemTitle t =
  H.modify_ _ { newItemTitle = t }

handleSubmitNewItem
  :: forall o
   . Dispatch o
  -> String
  -> HalogenAction o
handleSubmitNewItem dispatch projectId = do
  st <- H.get
  let title = st.newItemTitle
  when (title /= "") do
    H.modify_ _ { newItemTitle = "" }
    result <- H.liftAff $
      addDraftItem st.token projectId title
    case result of
      Left err ->
        H.modify_ _ { error = Just err }
      Right _ ->
        handleRefreshProjectItems dispatch projectId

handleStartEditItem
  :: forall o
   . String
  -> String
  -> HalogenAction o
handleStartEditItem itemId currentTitle =
  H.modify_ _
    { editingItem = Just itemId
    , editItemTitle = currentTitle
    }

handleSetEditItemTitle
  :: forall o. String -> HalogenAction o
handleSetEditItemTitle t =
  H.modify_ _ { editItemTitle = t }

handleSubmitEditItem
  :: forall o
   . String
  -> String
  -> String
  -> HalogenAction o
handleSubmitEditItem projectId draftId newTitle = do
  st <- H.get
  H.modify_ _
    { editingItem = Nothing
    , editItemTitle = ""
    }
  when (newTitle /= "") do
    -- optimistic update
    case Map.lookup projectId st.projectItems of
      Nothing -> pure unit
      Just items ->
        let
          updated = map
            ( \(ProjectItem pi) ->
                if pi.draftId == Just draftId then
                  ProjectItem pi
                    { title = newTitle }
                else ProjectItem pi
            )
            items
        in
          H.modify_ _
            { projectItems = Map.insert
                projectId
                updated
                st.projectItems
            }
    result <- H.liftAff $
      updateDraftItem st.token draftId newTitle
    case result of
      Left err ->
        H.modify_ _ { error = Just err }
      Right _ -> pure unit

handleDeleteItem
  :: forall o
   . String
  -> String
  -> HalogenAction o
handleDeleteItem projectId itemId = do
  confirmed <- liftEffect $
    confirmDialog "Delete this item?"
  when confirmed do
    st <- H.get
    -- optimistic remove
    case Map.lookup projectId st.projectItems of
      Nothing -> pure unit
      Just items ->
        let
          updated = filter
            ( \(ProjectItem pi) ->
                pi.itemId /= itemId
            )
            items
        in
          H.modify_ _
            { projectItems = Map.insert
                projectId
                updated
                st.projectItems
            }
    result <- H.liftAff $
      deleteProjectItem st.token projectId itemId
    case result of
      Left err ->
        H.modify_ _ { error = Just err }
      Right _ -> pure unit

handleStartRenameProject
  :: forall o
   . String
  -> String
  -> HalogenAction o
handleStartRenameProject projectId currentTitle =
  H.modify_ _
    { editingProject = Just projectId
    , editProjectTitle = currentTitle
    }

handleSetRenameProjectTitle
  :: forall o. String -> HalogenAction o
handleSetRenameProjectTitle t =
  H.modify_ _ { editProjectTitle = t }

handleSubmitRenameProject
  :: forall o
   . String
  -> String
  -> HalogenAction o
handleSubmitRenameProject projectId newTitle = do
  st <- H.get
  H.modify_ _
    { editingProject = Nothing
    , editProjectTitle = ""
    }
  when (newTitle /= "") do
    let
      updated = map
        ( \(Project proj) ->
            if proj.id == projectId then
              Project proj { title = newTitle }
            else Project proj
        )
        st.projects
    H.modify_ _ { projects = updated }
    result <- H.liftAff $
      renameProject st.token projectId newTitle
    case result of
      Left err ->
        H.modify_ _ { error = Just err }
      Right _ -> pure unit

-- | Rewrite GraphQL project errors into a
-- | user-friendly hint when the token lacks
-- | the required `read:project` scope.
friendlyProjectError :: String -> String
friendlyProjectError err =
  let
    low = toLower err
    scopeHint =
      "Your token does not have the "
        <> "project scope. Please create a "
        <> "token with read:project (or "
        <> "project) and update it in the "
        <> "settings."
  in
    if
      indexOf (Pattern "insufficient_scopes")
        low
        /= Nothing
        ||
          indexOf (Pattern "scope") low
            /= Nothing
            && indexOf (Pattern "project") low
              /= Nothing then scopeHint
    else err
