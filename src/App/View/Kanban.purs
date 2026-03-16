-- | Kanban view — three-column board backed by
-- | a GitHub Project.
module App.View.Kanban
  ( renderKanban
  , renderProjectSetup
  ) where

import Prelude

import Data.Array (filter, null)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Set as Set
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Lib.Types
  ( Page(..)
  , Project(..)
  , ProjectItem(..)
  )
import App.View.Types (Action(..), State)
import App.View.Widgets (refreshButton)

-- | Project setup — shown when no kanban project
-- | is configured.
renderProjectSetup
  :: forall w. State -> HH.HTML w Action
renderProjectSetup state =
  HH.div
    [ HP.class_ (HH.ClassName "kanban-setup") ]
    [ HH.h2_ [ HH.text "Select a project" ]
    , HH.p
        [ HP.class_ (HH.ClassName "muted") ]
        [ HH.text
            "Choose a GitHub Project to use as your Kanban board."
        ]
    , if state.projectsLoading then
        HH.p_ [ HH.text "Loading projects..." ]
      else if null state.projects then
        HH.div_
          [ HH.p
              [ HP.class_ (HH.ClassName "muted") ]
              [ HH.text "No projects found." ]
          , refreshButton RefreshProjects
          ]
      else
        HH.div
          [ HP.class_
              (HH.ClassName "kanban-project-list")
          ]
          ( map renderProjectOption state.projects
          )
    ]

-- | A single project option in the setup list.
renderProjectOption
  :: forall w. Project -> HH.HTML w Action
renderProjectOption (Project p) =
  HH.div
    [ HP.class_
        (HH.ClassName "kanban-project-option")
    , HE.onClick \_ -> SetKanbanProject p.id
    ]
    [ HH.span
        [ HP.class_
            (HH.ClassName "kanban-project-title")
        ]
        [ HH.text p.title ]
    , HH.span
        [ HP.class_
            (HH.ClassName "kanban-project-count")
        ]
        [ HH.text
            (show p.itemCount <> " items")
        ]
    ]

-- | Main kanban view — renders the current column.
renderKanban
  :: forall w. State -> HH.HTML w Action
renderKanban state =
  case state.kanbanProject of
    Nothing -> renderProjectSetup state
    Just projId ->
      let
        items = fromMaybe []
          (Map.lookup projId state.projectItems)
        columnStatus = case state.currentPage of
          BacklogPage -> "Backlog"
          WIPPage -> "WIP"
          DonePage -> "Done"
          _ -> "WIP"
        columnItems = filter
          ( \(ProjectItem pi) ->
              fromMaybe "" pi.status == columnStatus
          )
          items
      in
        HH.div
          [ HP.class_ (HH.ClassName "kanban-view") ]
          [ renderKanbanHeader state projId
              columnStatus
          , if null columnItems then
              HH.p
                [ HP.class_ (HH.ClassName "muted") ]
                [ HH.text
                    ( "No items in "
                        <> columnStatus
                    )
                ]
            else
              HH.div
                [ HP.class_
                    (HH.ClassName "kanban-items")
                ]
                (map (renderKanbanItem state projId)
                    columnItems
                )
          ]

-- | Column header with item count and refresh.
renderKanbanHeader
  :: forall w
   . State
  -> String
  -> String
  -> HH.HTML w Action
renderKanbanHeader state projId columnStatus =
  HH.div
    [ HP.class_ (HH.ClassName "kanban-header") ]
    [ HH.h2_
        [ HH.text columnStatus ]
    , refreshButton
        (RefreshProjectItems projId)
    ]

-- | A single kanban item row.
renderKanbanItem
  :: forall w
   . State
  -> String
  -> ProjectItem
  -> HH.HTML w Action
renderKanbanItem state projId (ProjectItem pi) =
  let
    itemKey = case pi.repoName of
      Just rn -> case pi.number of
        Just n -> Just (rn <> "#" <> show n)
        Nothing -> Nothing
      Nothing -> Nothing
    hasWorktree = case itemKey of
      Just k -> Set.member k state.agentWorktrees
      Nothing -> false
    hasBranch = case itemKey of
      Just k -> Map.member k state.agentBranches
      Nothing -> false
    hasSession = case itemKey of
      Just k -> Map.member k state.agentSessions
      Nothing -> false
    sessionState = case itemKey of
      Just k -> map _.state
        (Map.lookup k state.agentSessions)
      Nothing -> Nothing
    status = fromMaybe "" pi.status
    isExpanded = Set.member pi.itemId
      state.expandedItems
  in
    HH.div
      [ HP.class_
          ( HH.ClassName
              ( "kanban-item"
                  <> if hasSession then
                    " kanban-item-active"
                  else ""
              )
          )
      ]
      [ HH.div
          [ HP.class_
              (HH.ClassName "kanban-item-main")
          , HE.onClick \_ -> ToggleItem pi.itemId
          ]
          [ case pi.number of
              Just n ->
                HH.span
                  [ HP.class_
                      (HH.ClassName "kanban-item-num")
                  ]
                  [ HH.text ("#" <> show n) ]
              Nothing -> HH.text ""
          , HH.span
              [ HP.class_
                  (HH.ClassName "kanban-item-title")
              ]
              [ HH.text pi.title ]
          , HH.span
              [ HP.class_
                  (HH.ClassName "kanban-item-badges")
              ]
              [ if hasBranch then
                  HH.span
                    [ HP.class_
                        (HH.ClassName "badge")
                    , HP.title "Has branch"
                    ]
                    [ HH.text "\x2387" ]
                else HH.text ""
              , if hasWorktree then
                  HH.span
                    [ HP.class_
                        (HH.ClassName "badge")
                    , HP.title "Has worktree"
                    ]
                    [ HH.text "\x1F333" ]
                else HH.text ""
              , case sessionState of
                  Just st ->
                    HH.span
                      [ HP.class_
                          (HH.ClassName "badge")
                      , HP.title
                          ("Session: " <> st)
                      ]
                      [ HH.text "\x25C9" ]
                  Nothing -> HH.text ""
              ]
          , renderMoveButtons state projId
              pi.itemId
              status
          ]
      , if isExpanded then
          case pi.body of
            Just b | b /= "" ->
              HH.div
                [ HP.class_
                    (HH.ClassName "kanban-item-body")
                ]
                [ HH.text b ]
            _ ->
              HH.div
                [ HP.class_
                    (HH.ClassName "kanban-item-body muted")
                ]
                [ HH.text "No description" ]
        else HH.text ""
      ]

-- | Move left/right buttons for kanban items.
renderMoveButtons
  :: forall w
   . State
  -> String
  -> String
  -> String
  -> HH.HTML w Action
renderMoveButtons _state projId itemId status =
  HH.span
    [ HP.class_
        (HH.ClassName "kanban-move-buttons")
    ]
    [ if status /= "Backlog" then
        HH.button
          [ HE.onClick \_ ->
              SetItemStatus projId itemId
                (prevStatus status)
          , HP.class_ (HH.ClassName "btn-hide")
          , HP.title
              ("Move to " <> prevStatus status)
          ]
          [ HH.text "\x25C0" ]
      else HH.text ""
    , if status /= "Done" then
        HH.button
          [ HE.onClick \_ ->
              SetItemStatus projId itemId
                (nextStatus status)
          , HP.class_ (HH.ClassName "btn-hide")
          , HP.title
              ("Move to " <> nextStatus status)
          ]
          [ HH.text "\x25B6" ]
      else HH.text ""
    ]

prevStatus :: String -> String
prevStatus "WIP" = "Backlog"
prevStatus "Done" = "WIP"
prevStatus s = s

nextStatus :: String -> String
nextStatus "Backlog" = "WIP"
nextStatus "WIP" = "Done"
nextStatus s = s
