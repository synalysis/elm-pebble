module Pebble.Compass exposing (Error(..), Heading, current, onChange)

{-| Read compass heading from watches with a magnetometer.

Request an initial reading in `init`, then subscribe for live heading updates.

    import Pebble.Compass as Compass

    type Msg
        = GotHeading (Result Compass.Error Compass.Heading)
        | HeadingChanged Compass.Heading

    init _ =
        ( model, Compass.current GotHeading )

    subscriptions _ =
        Compass.onChange HeadingChanged

For a runnable example, use the **watch-demo-compass** project template in the IDE.

@docs Error, Heading, current, onChange

-}

import Elm.Kernel.PebbleWatch


{-| Compass errors returned at the app boundary.
-}
type Error
    = Unavailable
    | InvalidReading


{-| A compass heading in degrees (0–360) when valid.
-}
type alias Heading =
    { degrees : Float
    , isValid : Bool
    }


{-| Request the current heading once.
-}
current : (Result Error Heading -> msg) -> Cmd msg
current =
    Elm.Kernel.PebbleWatch.compassCurrent


{-| Receive heading updates when the compass service reports changes.
-}
onChange : (Heading -> msg) -> Sub msg
onChange =
    Elm.Kernel.PebbleWatch.onCompassChange
