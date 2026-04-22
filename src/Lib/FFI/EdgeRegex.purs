-- | FFI helper: scan an issue body for dependency
-- | references anchored by keywords like "blocked by"
-- | or "blocks".
module Lib.FFI.EdgeRegex
  ( ScanHit
  , scanEdges
  ) where

-- | Single hit: kind ("blockedBy" or "blocking"), optional
-- | repo ("" if the reference omitted the `owner/repo`
-- | prefix), and issue number.
type ScanHit =
  { kind :: String
  , repo :: String
  , number :: Int
  }

foreign import scanEdges :: String -> Array ScanHit
