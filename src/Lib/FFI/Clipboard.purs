-- | FFI to copy text to the system clipboard.
module Lib.FFI.Clipboard (copyToClipboard) where

import Prelude

import Effect (Effect)

-- | Copy the given string to the clipboard.
foreign import copyToClipboard :: String -> Effect Unit
