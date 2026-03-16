-- | Agents view — landing page showing agent
-- | session status at a glance.
module App.View.Agents
  ( renderAgents
  ) where

import Prelude

import Data.Array (filter, length, null, sort)
import Data.Int (fromString) as Int
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Data.String as Data.String
import Data.String.CodeUnits as Data.String.CodeUnits
import Data.Tuple (Tuple(..))
import Halogen.HTML as HH
import Halogen.HTML.Core (AttrName(..))
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Lib.UI.Widgets (renderLabelSelector)
import App.View.Widgets (refreshButton)
import App.View.Types (Action(..), State)
import Lib.UI.Helpers (termElementId)

-- | Main agents view — shows all agent sessions
-- | grouped by status.
renderAgents
  :: forall w. State -> HH.HTML w Action
renderAgents state =
  HH.div
    [ HP.class_ (HH.ClassName "agents-view") ]
    [ renderAgentHeader state
    , if Map.isEmpty state.agentSessions
        && Set.isEmpty state.agentWorktrees
        then renderEmptyState state
      else renderSessionList state
    ]

-- | Header with refresh and status filter.
renderAgentHeader
  :: forall w. State -> HH.HTML w Action
renderAgentHeader state =
  HH.div
    [ HP.class_ (HH.ClassName "agents-header") ]
    [ HH.div
        [ HP.class_
            (HH.ClassName "agents-title-row")
        ]
        [ HH.h2_
            [ HH.text "Agent Sessions" ]
        , refreshButton RefreshAgentSessions
        , if state.agentServer == "" then
            HH.span
              [ HP.class_
                  (HH.ClassName "muted")
              ]
              [ HH.text
                  "Set agent server URL →"
              ]
          else HH.text ""
        ]
    , if not (Map.isEmpty state.agentSessions)
        then
          let
            statuses = collectStatuses state
          in
            if length statuses > 1 then
              renderLabelSelector
                state.sessionFilters
                ToggleSessionFilter
                statuses
            else HH.text ""
      else HH.text ""
    ]

-- | Empty state — no sessions, no worktrees.
renderEmptyState
  :: forall w. State -> HH.HTML w Action
renderEmptyState state =
  HH.div
    [ HP.class_ (HH.ClassName "agents-empty") ]
    [ HH.p
        [ HP.class_ (HH.ClassName "muted") ]
        [ HH.text
            ( if state.agentServer == "" then
                "Configure an agent server to monitor sessions."
              else
                "No active sessions. Launch an agent from the Projects tab."
            )
        ]
    ]

-- | List of all sessions + worktrees.
renderSessionList
  :: forall w. State -> HH.HTML w Action
renderSessionList state =
  let
    entries = Map.toUnfoldable state.agentSessions
      :: Array (Tuple String String)
    filtered =
      if Set.isEmpty state.sessionFilters then
        entries
      else filter
        ( \(Tuple _ s) ->
            Set.member s state.sessionFilters
        )
        entries
    worktreeOnly = Set.toUnfoldable
      ( Set.difference state.agentWorktrees
          ( Set.fromFoldable
              (map (\(Tuple k _) -> k) entries)
          )
      ) :: Array String
  in
    HH.div
      [ HP.class_ (HH.ClassName "agents-list") ]
      [ if not (null filtered) then
          HH.div_
            ( map (renderSessionRow state) filtered
            )
        else HH.text ""
      , if not (null worktreeOnly) then
          HH.div_
            [ HH.h3
                [ HP.class_
                    (HH.ClassName "agents-section-title")
                ]
                [ HH.text "Worktrees (no session)" ]
            , HH.div_
                ( map renderWorktreeRow worktreeOnly
                )
            ]
        else HH.text ""
      ]

-- | A single agent session row.
renderSessionRow
  :: forall w
   . State
  -> Tuple String String
  -> HH.HTML w Action
renderSessionRow state (Tuple key status) =
  let
    hasTerminal =
      Set.member key state.launchedItems
    hasWorktree =
      Set.member key state.agentWorktrees
  in
    HH.div
      [ HP.class_
          ( HH.ClassName
              ( "agent-row agent-"
                  <> statusClass status
              )
          )
      ]
      [ HH.div
          [ HP.class_
              (HH.ClassName "agent-row-main")
          ]
          [ HH.span
              [ HP.class_
                  ( HH.ClassName
                      ( "agent-status-badge badge-"
                          <> statusClass status
                      )
                  )
              ]
              [ HH.text (statusIcon status) ]
          , HH.span
              [ HP.class_
                  (HH.ClassName "agent-key")
              ]
              [ HH.text key ]
          , HH.span
              [ HP.class_
                  (HH.ClassName "agent-status-text")
              ]
              [ HH.text status ]
          , if hasWorktree then
              HH.span
                [ HP.class_
                    (HH.ClassName "agent-badge")
                , HP.title "Has worktree"
                ]
                [ HH.text "\x1F333" ]
            else HH.text ""
          , renderSessionActions key hasTerminal
          ]
      , if hasTerminal then
          HH.div
            [ HP.class_
                (HH.ClassName "agent-terminal")
            , HP.id (termElementId key)
            , HP.attr (AttrName "data-key") key
            ]
            []
        else HH.text ""
      ]

-- | Action buttons for a session row.
renderSessionActions
  :: forall w
   . String
  -> Boolean
  -> HH.HTML w Action
renderSessionActions key hasTerminal =
  let
    parts = parseKey key
  in
    HH.div
      [ HP.class_
          (HH.ClassName "agent-actions")
      ]
      ( case parts of
          Just { repo, issue } ->
            if hasTerminal then
              [ HH.button
                  [ HE.onClick \_ ->
                      DetachAgent repo issue
                  , HP.class_
                      (HH.ClassName "btn-hide")
                  , HP.title "Detach terminal"
                  ]
                  [ HH.text "\x23CF" ]
              , HH.button
                  [ HE.onClick \_ ->
                      StopAgent repo issue
                  , HP.class_
                      (HH.ClassName "btn-hide")
                  , HP.title "Stop agent"
                  ]
                  [ HH.text "\x23F9" ]
              ]
            else
              [ HH.button
                  [ HE.onClick \_ ->
                      LaunchAgent key repo issue
                  , HP.class_
                      (HH.ClassName "btn-hide")
                  , HP.title "Attach terminal"
                  ]
                  [ HH.text "\x25B6" ]
              ]
          Nothing -> []
      )

-- | A worktree-only row (no active session).
renderWorktreeRow
  :: forall w. String -> HH.HTML w Action
renderWorktreeRow key =
  HH.div
    [ HP.class_
        (HH.ClassName "agent-row agent-idle")
    ]
    [ HH.div
        [ HP.class_
            (HH.ClassName "agent-row-main")
        ]
        [ HH.span
            [ HP.class_
                ( HH.ClassName
                    "agent-status-badge badge-idle"
                )
            ]
            [ HH.text "\x25CB" ]
        , HH.span
            [ HP.class_
                (HH.ClassName "agent-key")
            ]
            [ HH.text key ]
        , HH.span
            [ HP.class_
                (HH.ClassName "agent-status-text")
            ]
            [ HH.text "worktree only" ]
        , HH.span
            [ HP.class_
                (HH.ClassName "agent-badge")
            , HP.title "Has worktree"
            ]
            [ HH.text "\x1F333" ]
        ]
    ]

-- | Collect unique session statuses with counts.
collectStatuses
  :: State
  -> Array { name :: String, count :: Int }
collectStatuses state =
  let
    allStatuses =
      Map.values state.agentSessions
    unique = sort $ Set.toUnfoldable
      $ Set.fromFoldable allStatuses
  in
    map
      ( \s ->
          { name: s
          , count:
              length
                ( filter (_ == s)
                    (Map.values state.agentSessions)
                )
          }
      )
      unique

-- | Map status to CSS class.
statusClass :: String -> String
statusClass "running" = "running"
statusClass "waiting" = "waiting"
statusClass "completed" = "completed"
statusClass "error" = "error"
statusClass _ = "unknown"

-- | Map status to icon.
statusIcon :: String -> String
statusIcon "running" = "\x25CF"
statusIcon "waiting" = "\x25D4"
statusIcon "completed" = "\x2713"
statusIcon "error" = "\x2717"
statusIcon _ = "\x25CB"

-- | Parse "owner/repo#issue" into components.
parseKey
  :: String
  -> Maybe { repo :: String, issue :: Int }
parseKey key =
  let
    parts = splitAt '#' key
  in
    case parts of
      Just { before: repo, after: issueStr } ->
        case Int.fromString issueStr of
          Just n -> Just { repo, issue: n }
          Nothing -> Nothing
      Nothing -> Nothing

-- | Split string at first occurrence of char.
splitAt
  :: Char
  -> String
  -> Maybe { before :: String, after :: String }
splitAt c str =
  let
    pat = Data.String.Pattern
      (Data.String.CodeUnits.singleton c)
  in
    case Data.String.indexOf pat str of
      Just idx ->
        Just
          { before: Data.String.take idx str
          , after: Data.String.drop (idx + 1) str
          }
      Nothing -> Nothing

