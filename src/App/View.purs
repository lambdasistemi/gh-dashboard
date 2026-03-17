-- | View — top-level render functions and shared types.
module App.View
  ( module App.View.Types
  , renderTokenForm
  , renderDashboard
  ) where

import Prelude

import Data.Array (null)
import Data.Maybe (Maybe(..))
import Lib.GitHub (RateLimit)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Lib.Types (Page(..), Repo)
import App.View.Kanban (renderFilters, renderKanban)
import Lib.UI.Widgets (settingsRow)
import App.View.Projects (renderProjects)
import App.View.RepoTable (renderRepoTable)
import App.View.Types (Action(..), State, Toast, ToastLevel(..))

-- | Token input form shown when no token is set.
renderTokenForm
  :: forall w
   . State
  -> HH.HTML w Action
renderTokenForm state =
  HH.div
    [ HP.class_ (HH.ClassName "form-container") ]
    [ HH.h1_ [ HH.text "GH Dashboard" ]
    , HH.p
        [ HP.class_ (HH.ClassName "muted") ]
        [ HH.text
            "Your GitHub repositories at a glance"
        ]
    , HH.div
        [ HP.class_ (HH.ClassName "form") ]
        [ HH.input
            [ HP.type_ HP.InputPassword
            , HP.placeholder "GitHub personal access token"
            , HP.value state.token
            , HE.onValueInput SetToken
            , HP.class_ (HH.ClassName "input")
            ]
        , HH.button
            [ HE.onClick \_ -> SubmitToken
            , HP.class_ (HH.ClassName "btn")
            ]
            [ HH.text "Connect" ]
        ]
    , case state.error of
        Just err ->
          HH.div
            [ HP.class_ (HH.ClassName "error") ]
            [ HH.text err ]
        Nothing -> HH.text ""
    , HH.div
        [ HP.class_ (HH.ClassName "instructions") ]
        [ HH.h3_ [ HH.text "Getting started" ]
        , HH.ol_
            [ HH.li_
                [ HH.a
                    [ HP.href
                        "https://github.com/settings/tokens/new?scopes=repo,read:project&description=gh-dashboard"
                    , HP.target "_blank"
                    , HP.class_
                        (HH.ClassName "token-link")
                    ]
                    [ HH.text
                        "Create a GitHub token"
                    ]
                , HH.text " (select "
                , HH.code_ [ HH.text "repo" ]
                , HH.text " and "
                , HH.code_
                    [ HH.text "read:project" ]
                , HH.text " scopes)"
                ]
            , HH.li_
                [ HH.text
                    "Paste it above and click Connect"
                ]
            , HH.li_
                [ HH.text
                    "Browse your repos, expand for issues and PRs"
                ]
            ]
        ]
    ]

-- | Full dashboard view with toolbar and repo table.
renderDashboard
  :: forall w
   . State
  -> Array Repo
  -> HH.HTML w Action
renderDashboard state repos =
  HH.div
    [ HP.style "padding: 0.5em;" ]
    [ renderToasts state.toasts
    , renderToolbar state
    , case state.error of
        Just err ->
          HH.div
            [ HP.class_ (HH.ClassName "error") ]
            [ HH.text err ]
        Nothing -> HH.text ""
    , case state.currentPage of
        BacklogPage -> renderKanban state
        WIPPage -> renderKanban state
        DonePage -> renderKanban state
        FiltersPage -> renderFilters state
        SettingsPage -> renderSettings state
        ReposPage -> renderKanban state
        ProjectsPage -> renderKanban state
    ]

-- | Toolbar with filter and controls.
renderToolbar
  :: forall w. State -> HH.HTML w Action
renderToolbar state =
  HH.div
    [ HP.class_ (HH.ClassName "toolbar") ]
    [ HH.div
        [ HP.class_ (HH.ClassName "tab-bar") ]
        [ HH.button
            [ HE.onClick \_ ->
                SwitchPage BacklogPage
            , HP.class_
                ( HH.ClassName
                    ( "tab-btn"
                        <> activeIf
                          ( state.currentPage
                              == BacklogPage
                          )
                    )
                )
            ]
            [ HH.text "Backlog" ]
        , HH.button
            [ HE.onClick \_ ->
                SwitchPage WIPPage
            , HP.class_
                ( HH.ClassName
                    ( "tab-btn"
                        <> activeIf
                          ( state.currentPage
                              == WIPPage
                          )
                    )
                )
            ]
            [ HH.text "WIP" ]
        , HH.button
            [ HE.onClick \_ ->
                SwitchPage DonePage
            , HP.class_
                ( HH.ClassName
                    ( "tab-btn"
                        <> activeIf
                          ( state.currentPage
                              == DonePage
                          )
                    )
                )
            ]
            [ HH.text "Done" ]
        , HH.button
            [ HE.onClick \_ ->
                SwitchPage FiltersPage
            , HP.class_
                ( HH.ClassName
                    ( "tab-btn"
                        <> activeIf
                          ( state.currentPage
                              == FiltersPage
                          )
                    )
                )
            ]
            [ HH.text "\x2AF6" ]
        , HH.button
            [ HE.onClick \_ ->
                SwitchPage SettingsPage
            , HP.class_
                ( HH.ClassName
                    ( "tab-btn"
                        <> activeIf
                          ( state.currentPage
                              == SettingsPage
                          )
                    )
                )
            ]
            [ HH.text "\x2699" ]
        ]
    ]

-- | Settings panel — clear labels, grouped sections.
renderSettings
  :: forall w. State -> HH.HTML w Action
renderSettings state =
  HH.div
    [ HP.class_
        (HH.ClassName "detail-section")
    ]
    [ HH.div
        [ HP.class_
            (HH.ClassName "detail-heading")
        ]
        [ HH.text "Settings" ]
    -- Agent server
    , settingsRow "Agent"
        "URL of the agent daemon that manages sessions and worktrees"
        [ HH.input
            [ HP.value state.agentServer
            , HE.onValueInput SetAgentServer
            , HP.style
                "padding:6px 10px; border:1px solid var(--border); border-radius:4px; background:var(--bg-surface); color:var(--text); font-size:12px; outline:none; width:100%; box-sizing:border-box"
            , HP.placeholder "server URL"
            ]
        ]
    -- Rate limit
    , settingsRow "GitHub API"
        "Remaining API calls for this token"
        [ renderRateLimit state.rateLimit ]
    -- Theme
    , settingsRow "Theme"
        "Switch between dark and light mode"
        [ HH.button
            [ HE.onClick \_ -> ToggleTheme
            , HP.class_ (HH.ClassName "btn-small")
            ]
            [ HH.text
                ( if state.darkTheme then
                    "Switch to light"
                  else "Switch to dark"
                )
            ]
        ]
    -- Data
    , settingsRow "Data"
        "Export or import your settings, or reset everything"
        [ HH.button
            [ HE.onClick \_ -> ExportStorage
            , HP.class_ (HH.ClassName "btn-small")
            ]
            [ HH.text "Export" ]
        , HH.button
            [ HE.onClick \_ -> ImportStorage
            , HP.class_ (HH.ClassName "btn-small")
            ]
            [ HH.text "Import" ]
        , HH.button
            [ HE.onClick \_ -> ResetToken
            , HP.class_ (HH.ClassName "btn-small")
            ]
            [ HH.text "Reset token" ]
        , HH.button
            [ HE.onClick \_ -> ResetAll
            , HP.class_ (HH.ClassName "btn-small")
            ]
            [ HH.text "Reset all" ]
        ]
    -- Links
    , settingsRow "About"
        ""
        [ HH.a
            [ HP.href
                "https://github.com/lambdasistemi/gh-dashboard"
            , HP.target "_blank"
            , HP.class_ (HH.ClassName "link-btn")
            ]
            [ HH.text "Source code" ]
        ]
    ]


activeIf :: Boolean -> String
activeIf true = " active"
activeIf false = ""

-- | Toast notification container (bottom-right).
renderToasts
  :: forall w. Array Toast -> HH.HTML w Action
renderToasts toasts =
  HH.div
    [ HP.class_ (HH.ClassName "toast-container") ]
    (map renderToast toasts)

-- | A single toast notification with dismiss button.
renderToast
  :: forall w. Toast -> HH.HTML w Action
renderToast t =
  HH.div
    [ HP.class_
        ( HH.ClassName
            ( "toast toast-"
                <> case t.level of
                  ToastInfo -> "info"
                  ToastError -> "error"
            )
        )
    ]
    [ HH.span
        [ HP.class_ (HH.ClassName "toast-msg") ]
        [ HH.text t.message ]
    , HH.button
        [ HE.onClick \_ -> DismissToast t.id
        , HP.class_ (HH.ClassName "toast-close")
        ]
        [ HH.text "\x2715" ]
    ]

-- | Rate limit display.
renderRateLimit
  :: forall w i. Maybe RateLimit -> HH.HTML w i
renderRateLimit = case _ of
  Nothing -> HH.text ""
  Just rl ->
    HH.span
      [ HP.class_
          ( HH.ClassName
              ( if rl.remaining < 100 then
                  "rate-limit rate-limit-warn"
                else "rate-limit"
              )
          )
      ]
      [ HH.text
          ( show rl.remaining <> "/"
              <> show rl.limit
          )
      ]
