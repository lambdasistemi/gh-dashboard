-- | Reusable UI widgets that don't depend on
-- | app-specific types.
module Lib.UI.Widgets
  ( collectLabels
  , renderLabelSelector
  ) where

import Prelude

import Data.Array (concatMap, filter, length, sort, sortBy)
import Data.Function (on)
import Data.Set as Set
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP

-- | Collect unique label names with counts from items.
collectLabels
  :: Array (Array { name :: String })
  -> Array { name :: String, count :: Int }
collectLabels items =
  let
    allNames = map _.name (concatMap identity items)
    unique = sort $ Set.toUnfoldable $ Set.fromFoldable
      allNames
  in
    sortBy (flip compare `on` _.count) $ map
      ( \n ->
          { name: n
          , count: length (filter (_ == n) allNames)
          }
      )
      unique

-- | Vertical label selector with multi-select.
renderLabelSelector
  :: forall w action
   . Set.Set String
  -> (String -> action)
  -> Array { name :: String, count :: Int }
  -> HH.HTML w action
renderLabelSelector active toAction labels =
  HH.div
    [ HP.class_
        (HH.ClassName "label-selector")
    ]
    ( map
        ( \l ->
            HH.span
              [ HP.class_
                  ( HH.ClassName
                      ( "label-tag clickable"
                          <>
                            if Set.member l.name active then " active"
                            else ""
                      )
                  )
              , HE.onClick \_ -> toAction l.name
              ]
              [ HH.text
                  ( l.name <> " ("
                      <> show l.count
                      <> ")"
                  )
              ]
        )
        labels
    )
