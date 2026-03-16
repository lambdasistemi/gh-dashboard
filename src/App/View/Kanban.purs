-- | Kanban view — three-column board backed by
-- | a GitHub Project.
module App.View.Kanban
  ( renderKanban
  , renderProjectSetup
  , renderFilters
  ) where

import Prelude

import Data.Array
  ( any
  , filter
  , length
  , nubEq
  , null
  , sort
  )
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
  , StatusField
  )
import App.View.Projects (renderItemRow, renderRepoFilter)
import App.View.Widgets (refreshButton)
import App.View.Types (Action(..), State)

-- | The three required kanban statuses.
kanbanStatuses :: Array String
kanbanStatuses = [ "Backlog", "WIP", "Done" ]

-- | Filter a status field to only kanban statuses.
kanbanStatusField :: StatusField -> StatusField
kanbanStatusField sf = sf
  { options = filter
      (\o -> any (_ == o.name) kanbanStatuses)
      sf.options
  }

-- | Check if a status field has all required statuses.
hasRequiredStatuses :: StatusField -> Boolean
hasRequiredStatuses sf =
  let
    names = map _.name sf.options
  in
    any (_ == "Backlog") names
      && any (_ == "WIP") names
      && any (_ == "Done") names

-- | Apply repo and label filters to items.
applyKanbanFilters
  :: State -> Array ProjectItem -> Array ProjectItem
applyKanbanFilters state items =
  let
    repoFiltered =
      if Set.isEmpty state.projectRepoFilters then
        items
      else
        filter
          ( \(ProjectItem pi) ->
              Set.member
                (fromMaybe "(no repo)" pi.repoName)
                state.projectRepoFilters
          )
          items
    labelFiltered =
      if Set.isEmpty state.kanbanLabelFilters then
        repoFiltered
      else
        filter
          ( \(ProjectItem pi) ->
              any
                ( \l ->
                    Set.member l
                      state.kanbanLabelFilters
                )
                pi.labels
          )
          repoFiltered
  in
    labelFiltered

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
            "The project must have exactly three statuses: Backlog, WIP, Done."
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
        HH.div_
          [ HH.div
              [ HP.class_
                  (HH.ClassName "kanban-project-list")
              ]
              ( map
                  ( renderProjectOption state )
                  state.projects
              )
          , HH.div
              [ HP.class_
                  (HH.ClassName "kanban-create")
              ]
              [ HH.p
                  [ HP.class_
                      (HH.ClassName "muted")
                  ]
                  [ HH.text
                      "Or create a new project:"
                  ]
              , HH.button
                  [ HE.onClick \_ ->
                      CreateKanbanProject
                  , HP.class_
                      (HH.ClassName "btn")
                  ]
                  [ HH.text
                      "Create Kanban project"
                  ]
              , HH.p
                  [ HP.class_
                      (HH.ClassName "muted")
                  ]
                  [ HH.text
                      "After creation, rename the default statuses to Backlog, WIP, Done in GitHub."
                  ]
              ]
          ]
    ]

-- | A single project option in the setup list.
renderProjectOption
  :: forall w
   . State
  -> Project
  -> HH.HTML w Action
renderProjectOption state (Project p) =
  let
    mSf = Map.lookup p.id
      state.projectStatusFields
    valid = case mSf of
      Just sf -> hasRequiredStatuses sf
      Nothing -> false
    loaded = Map.member p.id
      state.projectStatusFields
  in
    HH.div
      [ HP.class_
          ( HH.ClassName
              ( "kanban-project-option"
                  <>
                    if valid then " valid"
                    else ""
              )
          )
      , if valid then
          HE.onClick \_ -> SetKanbanProject p.id
        else
          HE.onClick \_ ->
            RefreshProjectItems p.id
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
      , if not loaded then
          HH.span
            [ HP.class_ (HH.ClassName "muted") ]
            [ HH.text " (click to check)" ]
        else if valid then
          HH.span
            [ HP.class_
                (HH.ClassName "badge")
            ]
            [ HH.text " \x2713" ]
        else
          HH.span
            [ HP.class_
                (HH.ClassName "error")
            ]
            [ HH.text
                " Missing Backlog/WIP/Done statuses"
            ]
      ]

-- | Filters pane — repo and label selectors.
renderFilters
  :: forall w. State -> HH.HTML w Action
renderFilters state =
  case state.kanbanProject of
    Nothing ->
      HH.p
        [ HP.class_ (HH.ClassName "muted") ]
        [ HH.text "Select a project first." ]
    Just projId ->
      let
        items = fromMaybe []
          (Map.lookup projId state.projectItems)
        allLabels = sort $ nubEq $ items >>=
          \(ProjectItem pi) -> pi.labels
        activeLabels = Set.size
          state.kanbanLabelFilters
      in
        HH.div
          [ HP.class_
              (HH.ClassName "detail-section")
          ]
          [ HH.div
              [ HP.class_
                  (HH.ClassName "detail-heading")
              ]
              [ HH.text "Filters"
              , refreshButton
                  (RefreshProjectItems projId)
              ]
          , renderRepoFilter state items
          , HH.div
              [ HP.class_
                  (HH.ClassName "detail-section")
              ]
              [ HH.div
                  [ HP.class_
                      ( HH.ClassName
                          "detail-heading clickable"
                      )
                  , HE.onClick \_ ->
                      ToggleItem "kanban-label-filter"
                  ]
                  [ HH.text
                      ( ( if
                            Set.member
                              "kanban-label-filter"
                              state.expandedItems
                          then "\x25BE "
                          else "\x25B8 "
                        )
                          <> "Labels"
                          <>
                            if activeLabels > 0 then
                              " (" <> show activeLabels
                                <> " active)"
                            else ""
                      )
                  ]
              , if
                  not
                    ( Set.member "kanban-label-filter"
                        state.expandedItems
                    ) then HH.text ""
                else if null allLabels then
                  HH.p
                    [ HP.class_
                        (HH.ClassName "muted")
                    ]
                    [ HH.text "No labels found" ]
                else
                  HH.div
                    [ HP.class_
                        (HH.ClassName "label-selector")
                    ]
                    ( map
                        ( \lbl ->
                            HH.span
                              [ HP.class_
                                  ( HH.ClassName
                                      ( "label-tag clickable"
                                          <>
                                            if
                                              Set.member lbl
                                                state.kanbanLabelFilters
                                            then
                                              " active"
                                            else ""
                                      )
                                  )
                              , HE.onClick \_ ->
                                  ToggleKanbanLabelFilter
                                    lbl
                              ]
                              [ HH.text lbl ]
                        )
                        allLabels
                    )
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
        mSfRaw = Map.lookup projId
          state.projectStatusFields
        valid = case mSfRaw of
          Just sf -> hasRequiredStatuses sf
          Nothing -> true
      in
        if not valid then
          renderProjectSetup state
        else
          let
            allItems = fromMaybe []
              (Map.lookup projId state.projectItems)
            items = applyKanbanFilters state allItems
            columnStatus = case state.currentPage of
              BacklogPage -> "Backlog"
              WIPPage -> "WIP"
              DonePage -> "Done"
              _ -> "WIP"
            columnItems = filter
              ( \(ProjectItem pi) ->
                  fromMaybe "" pi.status
                    == columnStatus
              )
              items
            mSf = map kanbanStatusField mSfRaw
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
                            , HH.th_ []
                            ]
                        ]
                    , HH.tbody_
                        ( columnItems
                            >>= renderItemRow
                              state
                              projId
                              mSf
                        )
                    ]
              ]
