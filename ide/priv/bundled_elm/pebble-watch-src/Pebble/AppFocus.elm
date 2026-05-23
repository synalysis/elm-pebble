module Pebble.AppFocus exposing (State(..), onChange)

{-| Observe when the watch app gains or loses foreground focus.

@docs State, onChange

-}

import Elm.Kernel.PebbleWatch


{-| Whether the app is currently in the foreground.
-}
type State
    = InFocus
    | OutOfFocus


{-| Receive focus changes from the Pebble runtime.
-}
onChange : (State -> msg) -> Sub msg
onChange =
    Elm.Kernel.PebbleWatch.onAppFocusChange
