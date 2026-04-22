-- | Kanban view — three-column board backed by
-- | a GitHub Project.
module App.View.Kanban
  ( renderKanban
  , renderProjectSetup
  , renderFilters
  , columnCount
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
import Lib.UI.Widgets (settingsRow)
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
    [ HH.h2_ [ HH.text "Pick a Kanban project" ]
    , HH.p
        [ HP.class_ (HH.ClassName "muted") ]
        [ HH.text
            "This dashboard shows one GitHub Projects v2 board as a Backlog / WIP / Done Kanban. The project must have a Status field with those three options."
        ]
    , HH.ol
        [ HP.class_ (HH.ClassName "muted")
        , HP.style "padding-left:1.2em; margin:0 0 12px"
        ]
        [ HH.li_
            [ HH.text
                "Click "
            , HH.strong_ [ HH.text "Check" ]
            , HH.text
                " on a project to verify it has Backlog/WIP/Done."
            ]
        , HH.li_
            [ HH.text "If it's compatible, click "
            , HH.strong_ [ HH.text "Use this" ]
            , HH.text " to bind it."
            ]
        , HH.li_
            [ HH.text
                "No compatible project? Create one below."
            ]
        ]
    , if state.projectsLoading then
        HH.p_ [ HH.text "Loading projects\x2026" ]
      else if null state.projects then
        HH.div_
          [ HH.p
              [ HP.class_ (HH.ClassName "muted") ]
              [ HH.text "No projects found for this token." ]
          , refreshButton RefreshProjects
          ]
      else
        HH.div_
          [ HH.div
              [ HP.class_
                  (HH.ClassName "kanban-project-list")
              ]
              ( map
                  (renderProjectOption state)
                  state.projects
              )
          , HH.div
              [ HP.style "margin-top:8px" ]
              [ refreshButton RefreshProjects ]
          , HH.div
              [ HP.class_
                  (HH.ClassName "kanban-create")
              , HP.style
                  "margin-top:20px; padding-top:12px; border-top:1px solid var(--border)"
              ]
              [ HH.p
                  [ HP.class_
                      (HH.ClassName "muted")
                  ]
                  [ HH.text
                      "None of these work? Create a new one:"
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
                      "After creation, rename the default statuses to Backlog, WIP, Done in GitHub, then click "
                  , HH.strong_
                      [ HH.text "Check" ]
                  , HH.text " here."
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
    mSf = Map.lookup p.id state.projectStatusFields
    valid = case mSf of
      Just sf -> hasRequiredStatuses sf
      Nothing -> false
    loaded = Map.member p.id
      state.projectStatusFields
    checking = Set.member p.id
      state.projectsChecking
    statusBadge =
      if checking then
        HH.span
          [ HP.class_ (HH.ClassName "muted") ]
          [ HH.text "Checking\x2026" ]
      else if not loaded then
        HH.span
          [ HP.class_ (HH.ClassName "muted") ]
          [ HH.text "Not checked yet" ]
      else if valid then
        HH.span
          [ HP.class_ (HH.ClassName "badge")
          , HP.style "color:var(--ok,#3fb950)"
          ]
          [ HH.text "\x2713 Compatible" ]
      else
        HH.span
          [ HP.class_ (HH.ClassName "error") ]
          [ HH.text
              "\x2717 Needs Backlog/WIP/Done statuses"
          ]
    actionBtn =
      if checking then
        HH.button
          [ HP.disabled true
          , HP.class_ (HH.ClassName "btn-small")
          ]
          [ HH.text "Checking\x2026" ]
      else if valid then
        HH.button
          [ HE.onClick \_ -> SetKanbanProject p.id
          , HP.class_ (HH.ClassName "btn")
          ]
          [ HH.text "Use this" ]
      else if loaded then
        HH.button
          [ HP.disabled true
          , HP.class_ (HH.ClassName "btn-small")
          , HP.title
              "Rename the Status options on GitHub to Backlog, WIP, Done, then check again"
          ]
          [ HH.text "Not compatible" ]
      else
        HH.button
          [ HE.onClick \_ -> CheckProjectCompat p.id
          , HP.class_ (HH.ClassName "btn-small")
          ]
          [ HH.text "Check" ]
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
      , HP.style
          "display:flex; align-items:center; gap:10px; padding:8px 10px; border:1px solid var(--border); border-radius:4px; margin-bottom:6px"
      ]
      [ HH.div
          [ HP.style "flex:1; min-width:0" ]
          [ HH.div
              [ HP.class_
                  (HH.ClassName "kanban-project-title")
              , HP.style "font-weight:500"
              ]
              [ HH.text p.title ]
          , HH.div
              [ HP.style
                  "font-size:11px; color:var(--text-dim); margin-top:2px"
              ]
              [ HH.text (show p.itemCount <> " items \x00B7 ")
              , statusBadge
              ]
          ]
      , actionBtn
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
        labelKey = "kanban-label-filter"
        labelOpen = Set.member labelKey
          state.expandedItems
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
                      ToggleItem labelKey
                  ]
                  [ HH.text
                      ( ( if labelOpen then
                            "\x25BE "
                          else "\x25B8 "
                        )
                          <> "Labels"
                          <>
                            if activeLabels > 0 then
                              " ("
                                <> show activeLabels
                                <> " active)"
                            else ""
                      )
                  ]
              , if not labelOpen then HH.text ""
                else if null allLabels then
                  HH.p
                    [ HP.class_
                        (HH.ClassName "muted")
                    ]
                    [ HH.text "No labels" ]
                else
                  HH.div_
                    ( map
                        ( \lbl ->
                            HH.div
                              [ HP.class_
                                  ( HH.ClassName
                                      ( "filter-row clickable"
                                          <>
                                            if
                                              Set.member
                                                lbl
                                                state.kanbanLabelFilters then
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

-- | Count items in a column for a given status.
columnCount :: State -> String -> Int
columnCount state status =
  case state.kanbanProject of
    Nothing -> 0
    Just projId ->
      let
        allItems = fromMaybe []
          (Map.lookup projId state.projectItems)
        items = applyKanbanFilters state allItems
      in
        length $ filter
          ( \(ProjectItem pi) ->
              fromMaybe "" pi.status == status
          )
          items

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
              [ if null columnItems then
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
