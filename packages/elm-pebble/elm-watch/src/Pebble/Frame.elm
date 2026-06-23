module Pebble.Frame exposing
    ( Frame
    , atFps
    , every
    )

{-| Fixed-interval frame subscriptions.

Use these for games, animations, and smooth motion. `atFps` is a convenience
wrapper around `every` that converts frames-per-second to milliseconds.

    import Pebble.Frame as Frame

    type Msg
        = Tick Frame.Frame

    subscriptions _ =
        Frame.atFps 30 Tick

    update msg model =
        case msg of
            Tick frame ->
                ( { model | elapsedMs = frame.elapsedMs }, Cmd.none )

For a runnable example, use the **watch-demo-frame** project template in the IDE.

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
