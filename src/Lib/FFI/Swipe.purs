-- | Touch swipe detection for mobile navigation.
module Lib.FFI.Swipe
  ( onSwipe
  ) where

import Prelude (Unit)
import Effect (Effect)

foreign import onSwipeImpl
  :: Effect Unit -> Effect Unit -> Effect Unit

-- | Register swipe handlers. First callback is
-- | swipe-left, second is swipe-right.
onSwipe
  :: Effect Unit -> Effect Unit -> Effect Unit
onSwipe = onSwipeImpl
