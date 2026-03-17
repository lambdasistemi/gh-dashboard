-- | Application entry point and action dispatcher.
-- |
-- | This module is intentionally thin. It wires
-- | together:
-- |
-- | 1. **Halogen component** — initialState, render,
-- |    and the eval spec.
-- | 2. **Action dispatch** — routes each `Action` to
-- |    the appropriate handler module:
-- |    - `Action.Repos`    — repo/issue/PR/workflow
-- |    - `Action.Projects` — project board CRUD
-- |    - `Action.Agent`    — terminal/session mgmt
-- |    - Inline handlers   — trivial one-liners
-- |      (SetToken, ToggleTheme, etc.)
-- | 3. **Initialization** — loads persisted state from
-- |    localStorage, restores view, and kicks off
-- |    the first data fetch.
-- |
-- | If you're looking for the actual handler logic,
-- | see the `Action.*` modules. If you're looking for
-- | the view layer, see `View` and `View.*`.
module App.Main where

import Prelude

import Data.Either (Either(..))
import App.Action.Agent
  ( handleDetachAgent
  , handleLaunchAgent
  , handleRefreshAgentSessions
  , handleSetAgentServer
  , handleStopAgent
  , handleToggleSessionFilter
  )
import App.Action.Common
  ( persistView
  , toggleSet
  )
import App.Action.Projects
  ( handleDeleteItem
  , handleExpandProject
  , handleRefreshProjectItem
  , handleRefreshProjectItems
  , handleRefreshProjects
  , handleSetEditItemTitle
  , handleSetItemStatus
  , handleSetNewItemTitle
  , handleSetRenameProjectTitle
  , handleStartEditItem
  , handleStartRenameProject
  , handleSubmitEditItem
  , handleSubmitNewItem
  , handleSubmitRenameProject
  , handleToggleProjectRepoFilter
  )
import App.Action.Repos
  ( handleDragDrop
  , handleDragStart
  , handleHideItem
  , handleRefreshIssue
  , handleRefreshIssues
  , handleRefreshPR
  , handleRefreshPRs
  , handleRefreshRepo
  , handleRefreshWorkflows
  , handleRemoveRepo
  , handleSubmitAddRepo
  , handleToggleExpand
  , handleToggleItem
  , handleWorkflowNextSha
  , handleWorkflowPrevSha
  )
import Data.Array (null, filter)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Effect (Effect)
import Effect.Aff (Aff, Milliseconds(..), delay)
import Effect.Class (liftEffect)
import Lib.FFI.Cache as FFI.Cache
import Lib.FFI.Clipboard (copyToClipboard)
import Lib.FFI.Storage as FFIStorage
import Halogen.Subscription as HS
import Lib.FFI.Swipe (onSwipe)
import Lib.FFI.Theme (setBodyTheme)
import Halogen as H
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Lib.GitHub.GraphQL
  ( cachedUserProjects
  , cachedProjectItems
  , createKanbanProject
  )
import App.Refresh (doRefresh, loadCachedRepos)
import Lib.Util.Repo (applyFilter)
import App.Storage
  ( clearAll
  , clearToken
  , loadAgentServer
  , loadKanbanProject
  , loadRepoList
  , loadToken
  , loadViewState
  , saveKanbanProject
  , saveToken
  )
import Lib.Types (Page(..))
import App.View (Action(..), State, renderDashboard, renderTokenForm)
import Web.HTML (window)
import Web.HTML.Window (confirm)

main :: Effect Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  runUI rootComponent unit body

rootComponent
  :: forall q i o. H.Component q i o Aff
rootComponent =
  H.mkComponent
    { initialState: \_ -> initialState
    , render
    , eval: H.mkEval H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize
        }
    }

-- | Initial application state with all fields
-- | set to their empty/default values. Persisted
-- | state is loaded in the Initialize handler.
initialState :: State
initialState =
  { token: ""
  , repos: []
  , expanded: Nothing
  , details: Nothing
  , detailLoading: false
  , loading: false
  , error: Nothing
  , info: Nothing
  , rateLimit: Nothing
  , filterText: ""
  , hasToken: false
  , expandedItems: Set.empty
  , repoList: []
  , hiddenItems: Set.empty
  , dragging: Nothing
  , showAddRepo: false
  , addRepoInput: ""
  , darkTheme: true
  , issuesLoading: false
  , prsLoading: false
  , workflowsLoading: false
  , issueLabelFilters: Set.empty
  , prLabelFilters: Set.empty
  , workflowStatusFilters: Set.empty
  , currentPage: ReposPage
  , projects: []
  , projectsLoading: false
  , expandedProject: Nothing
  , projectItems: Map.empty
  , projectItemsLoading: false
  , projectRepoFilters: Set.empty
  , projectStatusFields: Map.empty
  , newItemTitle: ""
  , editingItem: Nothing
  , editItemTitle: ""
  , editingProject: Nothing
  , editProjectTitle: ""
  , kanbanProject: Nothing
  , agentServer: ""
  , launchedItems: Set.empty
  , terminalKeys: Map.empty
  , terminalUrls: Map.empty
  , agentSessions: Map.empty
  , agentWorktrees: Set.empty
  , agentBranches: Map.empty
  , kanbanLabelFilters: Set.empty
  , sessionFilters: Set.empty
  , toasts: []
  , nextToastId: 0
  }

render :: forall m. State -> H.ComponentHTML Action () m
render state =
  if state.hasToken then
    renderDashboard state
      (applyFilter state.filterText state.repos)
  else
    renderTokenForm state

------------------------------------------------------------
-- Action dispatcher
------------------------------------------------------------

-- | Route each action to its handler module.
-- |
-- | Cross-module calls (e.g. a project handler
-- | needing to refresh agent sessions) go through
-- | `handleAction` itself, passed as a `Dispatch`
-- | callback.
handleAction
  :: forall o
   . Action
  -> H.HalogenM State Action () o Aff Unit
handleAction = case _ of

  ------------------------------------------------
  -- Initialization & auth
  ------------------------------------------------

  Initialize -> do
    { emitter, listener } <- liftEffect HS.create
    _ <- H.subscribe emitter
    liftEffect $ onSwipe
      (HS.notify listener SwipeLeft)
      (HS.notify listener SwipeRight)
    saved <- H.liftAff loadToken
    repoList <- liftEffect loadRepoList
    agentUrl <- liftEffect loadAgentServer
    kbProject <- liftEffect loadKanbanProject
    vs <- liftEffect loadViewState
    liftEffect $ setBodyTheme vs.darkTheme
    H.modify_ _
      { repoList = repoList
      , kanbanProject = kbProject
      , agentServer = agentUrl
      , hiddenItems = vs.hiddenItems
      , darkTheme = vs.darkTheme
      , issueLabelFilters = vs.issueLabelFilters
      , prLabelFilters = vs.prLabelFilters
      , workflowStatusFilters =
          vs.workflowStatusFilters
      , currentPage = vs.currentPage
      , expanded = vs.expanded
      , expandedProject = vs.expandedProject
      , expandedItems = vs.expandedItems
      , filterText = vs.filterText
      , projectRepoFilters = vs.projectRepoFilters
      }
    case saved of
      "" -> pure unit
      tok -> do
        H.modify_ _
          { token = tok, hasToken = true }
        handleAction RefreshAgentSessions
        -- Load kanban project items if configured
        case kbProject of
          Just projId -> do
            cachedItems <- H.liftAff $
              cachedProjectItems projId
            case cachedItems of
              Just res ->
                H.modify_ _
                  { projectItems =
                      Map.insert projId
                        res.items
                        Map.empty
                  , projectItemsLoading = false
                  }
              Nothing -> pure unit
            handleAction
              (RefreshProjectItems projId)
          Nothing -> pure unit
        case vs.currentPage of
          BacklogPage -> pure unit
          WIPPage -> pure unit
          DonePage -> pure unit
          FiltersPage -> pure unit
          SettingsPage -> pure unit
          ReposPage -> do
            -- Show cached repos instantly
            _ <- loadCachedRepos
            -- Then refresh from network
            doRefresh tok
          ProjectsPage -> do
            -- Show cached projects instantly
            cachedProjs <- H.liftAff
              cachedUserProjects
            case cachedProjs of
              Just projs ->
                H.modify_ _
                  { projects = projs
                  , projectsLoading = false
                  }
              Nothing -> pure unit
            case vs.expandedProject of
              Nothing -> pure unit
              Just projId -> do
                cachedItems <- H.liftAff $
                  cachedProjectItems projId
                case cachedItems of
                  Just res ->
                    H.modify_ _
                      { projectItems =
                          Map.insert projId
                            res.items
                            Map.empty
                      , projectItemsLoading =
                          false
                      }
                  Nothing -> pure unit
            -- Then refresh from network
            handleAction RefreshProjects
            case vs.expandedProject of
              Nothing -> pure unit
              Just projId ->
                handleAction
                  (RefreshProjectItems projId)

  SetToken tok ->
    H.modify_ _ { token = tok }

  SubmitToken -> do
    st <- H.get
    if st.token == "" then
      H.modify_ _
        { error = Just "Please enter a token" }
    else do
      H.liftAff $ saveToken st.token
      H.modify_ _
        { hasToken = true
        , error = Nothing
        , loading = true
        }
      doRefresh st.token

  ------------------------------------------------
  -- Repo actions (delegated)
  ------------------------------------------------

  RefreshRepo fullName ->
    handleRefreshRepo fullName
  RefreshIssues ->
    handleRefreshIssues handleAction
  RefreshIssue n ->
    handleRefreshIssue n
  RefreshPRs ->
    handleRefreshPRs handleAction
  RefreshPR n ->
    handleRefreshPR n
  RefreshWorkflows ->
    handleRefreshWorkflows handleAction
  WorkflowPrevSha ->
    handleWorkflowPrevSha
  WorkflowNextSha ->
    handleWorkflowNextSha
  ToggleExpand fullName ->
    handleToggleExpand fullName
  ToggleItem key ->
    handleToggleItem handleAction key
  DragStart fullName ->
    handleDragStart fullName
  DragDrop targetName ->
    handleDragDrop targetName
  SubmitAddRepo ->
    handleSubmitAddRepo
  RemoveRepo fullName ->
    handleRemoveRepo fullName
  HideItem url ->
    handleHideItem url

  ------------------------------------------------
  -- Inline one-liners (not worth a module)
  ------------------------------------------------

  SetFilter txt -> do
    H.modify_ _ { filterText = txt }
    persistView

  ToggleAddRepo -> do
    st <- H.get
    H.modify_ _
      { showAddRepo = not st.showAddRepo
      , addRepoInput = ""
      }

  SetAddRepoInput txt ->
    H.modify_ _ { addRepoInput = txt }

  CopyText text ->
    liftEffect $ copyToClipboard text

  ToggleIssueLabelFilter label -> do
    st <- H.get
    H.modify_ _
      { issueLabelFilters =
          toggleSet label st.issueLabelFilters
      }
    persistView

  TogglePRLabelFilter label -> do
    st <- H.get
    H.modify_ _
      { prLabelFilters =
          toggleSet label st.prLabelFilters
      }
    persistView

  ToggleWorkflowStatusFilter status -> do
    st <- H.get
    H.modify_ _
      { workflowStatusFilters =
          toggleSet status st.workflowStatusFilters
      }
    persistView

  ToggleTheme -> do
    st <- H.get
    let dark = not st.darkTheme
    H.modify_ _ { darkTheme = dark }
    liftEffect $ setBodyTheme dark
    persistView

  ExportStorage ->
    liftEffect FFIStorage.exportStorage

  ImportStorage ->
    liftEffect FFIStorage.importStorage

  ResetToken -> do
    ok <- liftEffect do
      w <- window
      confirm "Reset token?" w
    when ok do
      liftEffect clearToken
      H.modify_ _
        { token = ""
        , hasToken = false
        }

  ResetAll -> do
    ok <- liftEffect do
      w <- window
      confirm "Reset all saved data?" w
    when ok do
      H.liftAff FFI.Cache.clearCache
      liftEffect do
        clearAll
        setBodyTheme true
      H.modify_ _
        { token = ""
        , hasToken = false
        , repos = []
        , repoList = []
        , hiddenItems = Set.empty
        , expanded = Nothing
        , details = Nothing
        , error = Nothing
        , info = Nothing
        , loading = false
        , darkTheme = true
        , projects = []
        , currentPage = ReposPage
        , expandedProject = Nothing
        , projectItems = Map.empty
        }

  SwitchPage page -> do
    H.modify_ _ { currentPage = page }
    persistView
    handleAction RefreshAgentSessions
    st <- H.get
    case page of
      BacklogPage -> pure unit
      WIPPage -> pure unit
      DonePage -> pure unit
      FiltersPage -> pure unit
      SettingsPage -> pure unit
      ProjectsPage ->
        when (null st.projects) do
          handleAction RefreshProjects
      ReposPage ->
        when (null st.repos) do
          doRefresh st.token

  ------------------------------------------------
  -- Project actions (delegated)
  ------------------------------------------------

  RefreshProjects ->
    handleRefreshProjects handleAction
  ExpandProject projectId ->
    handleExpandProject handleAction projectId
  RefreshProjectItems projectId ->
    handleRefreshProjectItems
      handleAction
      projectId
  RefreshProjectItem pid repo num ->
    handleRefreshProjectItem pid repo num
  ToggleProjectRepoFilter repo ->
    handleToggleProjectRepoFilter repo
  SetItemStatus pid iid status ->
    handleSetItemStatus handleAction pid iid status
  SetNewItemTitle t ->
    handleSetNewItemTitle t
  SubmitNewItem projectId ->
    handleSubmitNewItem handleAction projectId
  StartEditItem itemId title ->
    handleStartEditItem itemId title
  SetEditItemTitle t ->
    handleSetEditItemTitle t
  SubmitEditItem pid did title ->
    handleSubmitEditItem pid did title
  DeleteItem pid iid ->
    handleDeleteItem pid iid
  StartRenameProject pid title ->
    handleStartRenameProject pid title
  SetRenameProjectTitle t ->
    handleSetRenameProjectTitle t
  SubmitRenameProject pid title ->
    handleSubmitRenameProject pid title

  ------------------------------------------------
  -- Agent actions (delegated)
  ------------------------------------------------

  LaunchAgent toggleKey fullName issueNum ->
    handleLaunchAgent handleAction
      toggleKey
      fullName
      issueNum
  DetachAgent fullName issueNum ->
    handleDetachAgent handleAction fullName issueNum
  StopAgent fullName issueNum ->
    handleStopAgent handleAction
      fullName
      issueNum
  ToggleKanbanLabelFilter label ->
    H.modify_ \s -> s
      { kanbanLabelFilters =
          if Set.member label s.kanbanLabelFilters then Set.delete label s.kanbanLabelFilters
          else Set.insert label s.kanbanLabelFilters
      }
  SetKanbanProject projId -> do
    H.modify_ _ { kanbanProject = Just projId }
    liftEffect $ saveKanbanProject projId
    handleAction (RefreshProjectItems projId)
  CreateKanbanProject -> do
    st <- H.get
    result <- H.liftAff $
      createKanbanProject st.token
    case result of
      Left err ->
        H.modify_ _ { error = Just err }
      Right projId -> do
        handleAction RefreshProjects
        handleAction (SetKanbanProject projId)
  SetAgentServer url ->
    handleSetAgentServer url
  RefreshAgentSessions ->
    handleRefreshAgentSessions
  ToggleSessionFilter label ->
    handleToggleSessionFilter label

  ------------------------------------------------
  -- Toast notifications
  ------------------------------------------------

  SwipeLeft -> do
    st <- H.get
    case st.currentPage of
      BacklogPage -> handleAction (SwitchPage WIPPage)
      WIPPage -> handleAction (SwitchPage DonePage)
      DonePage -> handleAction (SwitchPage FiltersPage)
      FiltersPage -> handleAction (SwitchPage SettingsPage)
      _ -> pure unit
  SwipeRight -> do
    st <- H.get
    case st.currentPage of
      SettingsPage -> handleAction (SwitchPage FiltersPage)
      FiltersPage -> handleAction (SwitchPage DonePage)
      DonePage -> handleAction (SwitchPage WIPPage)
      WIPPage -> handleAction (SwitchPage BacklogPage)
      _ -> pure unit

  ShowToast msg level -> do
    st <- H.get
    let
      tid = st.nextToastId
      toast = { id: tid, message: msg, level }
    H.modify_ _
      { toasts = st.toasts <> [ toast ]
      , nextToastId = tid + 1
      }
    -- Auto-dismiss after 4 seconds
    H.liftAff $ delay (Milliseconds 4000.0)
    H.modify_ \s -> s
      { toasts = filter
          (\t -> t.id /= tid)
          s.toasts
      }

  DismissToast tid ->
    H.modify_ \s -> s
      { toasts = filter
          (\t -> t.id /= tid)
          s.toasts
      }
