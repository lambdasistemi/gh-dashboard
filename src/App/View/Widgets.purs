-- | App-specific widgets that depend on Action type.
module App.View.Widgets
  ( refreshButton
  , copyButton
  , hideButton
  , launchButton
  ) where

import Prelude

import Data.Set as Set
import Halogen.HTML as HH
import Halogen.HTML.Core (AttrName(..))
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import App.View.Types (Action(..))

-- | Refresh button for a single item.
refreshButton
  :: forall w. Action -> HH.HTML w Action
refreshButton action =
  HH.button
    [ HE.onClick \_ -> action
    , HP.class_ (HH.ClassName "btn-hide")
    , HP.title "Refresh"
    , HP.attr (AttrName "onclick")
        "event.stopPropagation()"
    ]
    [ HH.text "\x21BB" ]

-- | Copy title to clipboard button.
copyButton
  :: forall w. String -> HH.HTML w Action
copyButton text =
  HH.button
    [ HE.onClick \_ -> CopyText text
    , HP.class_ (HH.ClassName "btn-hide")
    , HP.title "Copy title"
    , HP.attr (AttrName "onclick")
        "event.stopPropagation()"
    ]
    [ HH.text "\x2398" ]

-- | Hide/unhide toggle button.
hideButton
  :: forall w. String -> Boolean -> HH.HTML w Action
hideButton url isHidden =
  HH.button
    [ HE.onClick \_ -> HideItem url
    , HP.class_ (HH.ClassName "btn-hide")
    , HP.title
        (if isHidden then "Unhide" else "Hide")
    ]
    [ HH.text
        (if isHidden then "\x25C9" else "\x25CC")
    ]

-- | Launch/detach/stop buttons for an issue agent.
launchButton
  :: forall w
   . Set.Set String
  -> String
  -> String
  -> Int
  -> Array (HH.HTML w Action)
launchButton launched toggleKey repoName issueNum =
  let
    key = repoName <> "#" <> show issueNum
    isActive = Set.member key launched
  in
    if isActive then
      [ HH.button
          [ HE.onClick \_ ->
              DetachAgent repoName issueNum
          , HP.class_ (HH.ClassName "btn-hide")
          , HP.title "Detach terminal"
          , HP.attr (AttrName "onclick")
              "event.stopPropagation()"
          ]
          [ HH.text "\x23CF" ]
      , HH.button
          [ HE.onClick \_ ->
              StopAgent repoName issueNum
          , HP.class_ (HH.ClassName "btn-hide")
          , HP.title "Stop agent"
          , HP.attr (AttrName "onclick")
              "event.stopPropagation()"
          ]
          [ HH.text "\x23F9" ]
      ]
    else
      [ HH.button
          [ HE.onClick \_ ->
              LaunchAgent toggleKey repoName
                issueNum
          , HP.class_ (HH.ClassName "btn-hide")
          , HP.title "Launch agent"
          , HP.attr (AttrName "onclick")
              "event.stopPropagation()"
          ]
          [ HH.text "\x25B6" ]
      ]
