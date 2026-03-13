-- | FFI to embed xterm.js terminals inline.
module FFI.Terminal
  ( attachTerminal
  , destroyTerminal
  , destroyOrphanedTerminals
  ) where

import Prelude

import Effect (Effect)

-- | Create an xterm.js terminal in the given DOM element
-- | and connect it via WebSocket. The launch key is
-- | stored so orphan cleanup can return it.
foreign import attachTerminal
  :: String -> String -> String -> Effect Unit

-- | Destroy all terminals whose container element
-- | was removed from the DOM. Returns the orphaned
-- | element IDs.
foreign import destroyOrphanedTerminals
  :: Effect (Array String)

-- | Destroy a terminal instance by element ID.
foreign import destroyTerminal
  :: String -> Effect Unit
