-- | Extract dependency edges from an issue body by
-- | scanning for keyword-anchored cross-repo references.
-- |
-- | Only references immediately preceded by a dependency
-- | keyword (`blocked by`, `depends on`, `blocks`, …)
-- | are kept, to avoid turning every incidental `#42`
-- | into an edge.
module Lib.Util.EdgeParse
  ( parseBodyEdges
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Lib.FFI.EdgeRegex (scanEdges, ScanHit)
import Lib.Types
  ( Edge(..)
  , EdgeKind(..)
  , EdgeSource(..)
  )

parseBodyEdges :: String -> String -> Array Edge
parseBodyEdges selfRepo body =
  map (hitToEdge selfRepo) (scanEdges body)

hitToEdge :: String -> ScanHit -> Edge
hitToEdge selfRepo hit = Edge
  { kind: case hit.kind of
      "blockedBy" -> EdgeBlockedBy
      "blocking" -> EdgeBlocking
      _ -> EdgeBlockedBy
  , source: SourceBody
  , repo: case hit.repo of
      "" -> selfRepo
      r -> r
  , number: hit.number
  , title: Nothing
  , url: Nothing
  }
