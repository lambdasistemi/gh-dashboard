-- | Kanban view — three-column board backed by
-- | a GitHub Project.
module App.View.Kanban
  ( renderKanban
  , renderProjectSetup
  ) where

import Prelude

import Data.Array (filter, length, null)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Lib.Types
  ( Page(..)
  , Project(..)
  , ProjectItem(..)
  )
import App.View.Projects (renderItemRow)
import App.View.Widgets (refreshButton)
import App.View.Types (Action(..), State)

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

-- | Main kanban view — renders the current column
-- | using the same table layout as the repos tab.
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
        mSf = Map.lookup projId
          state.projectStatusFields
        count = length columnItems
      in
        HH.div
          [ HP.class_
              (HH.ClassName "detail-section")
          ]
          [ HH.div
              [ HP.class_
                  (HH.ClassName "detail-heading")
              ]
              [ HH.text
                  ( columnStatus <> " ("
                      <> show count
                      <> ")"
                  )
              , refreshButton
                  (RefreshProjectItems projId)
              ]
          , if null columnItems then
              HH.div
                [ HP.class_
                    (HH.ClassName "empty-msg")
                ]
                [ HH.text
                    ( "No items in "
                        <> columnStatus
                    )
                ]
            else
              HH.table
                [ HP.class_
                    (HH.ClassName "detail-table")
                ]
                [ HH.thead_
                    [ HH.tr_
                        [ HH.th_ []
                        , HH.th_
                            [ HH.text "Title" ]
                        , HH.th_
                            [ HH.text "Repo" ]
                        , HH.th_
                            [ HH.text "Status" ]
                        ]
                    ]
                , HH.tbody_
                    ( columnItems >>= renderItemRow
                        state
                        projId
                        mSf
                    )
                ]
          ]
