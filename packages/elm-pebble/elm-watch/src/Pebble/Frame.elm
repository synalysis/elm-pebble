module Pebble.Frame exposing
    ( Frame
    , atFps
    , every
    )

{-| Fixed-interval frame subscriptions.

These subscriptions are useful for games, animations, and any watch app that
needs a regular update loop.

# Types
@docs Frame

# Subscriptions
@docs every, atFps

-}

import Elm.Kernel.PebbleWatch


{-| Information delivered with each frame.
-}
type alias Frame =
    { dtMs : Int
    , elapsedMs : Int
    , frame : Int
    }


{-| Receive a frame message every `intervalMs` milliseconds.
-}
every : Int -> (Frame -> msg) -> Sub msg
every intervalMs toMsg =
    Elm.Kernel.PebbleWatch.onFrame intervalMs toMsg


{-| Receive frame messages at the requested frames per second.
-}
atFps : Int -> (Frame -> msg) -> Sub msg
atFps fps toMsg =
    every (1000 // max 1 fps) toMsg
