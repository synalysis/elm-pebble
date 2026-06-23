module Pebble.UnobstructedArea exposing (currentBounds, onChanging, onDidChange, onWillChange)

{-| Observe Timeline Quick View unobstructed-area changes on round watches.

Use `currentBounds` during startup to sync the initial layout, then subscribe to
`onWillChange`, `onChanging`, and `onDidChange` to animate layout transitions.

    import Pebble.UnobstructedArea as UnobstructedArea
    import Pebble.Ui as Ui

    type Msg
        = GotBounds Ui.Rect
        | WillChange Ui.Rect
        | Changing Int
        | DidChange

    init _ =
        ( model, UnobstructedArea.currentBounds GotBounds )

    subscriptions _ =
        Sub.batch
            [ UnobstructedArea.onWillChange WillChange
            , UnobstructedArea.onChanging Changing
            , UnobstructedArea.onDidChange DidChange
            ]

For a runnable example, use the **watch-demo-unobstructed** project template in the IDE.

@docs onWillChange, onChanging, onDidChange, currentBounds

-}

import Elm.Kernel.PebbleWatch
import Pebble.Ui exposing (Rect)


{-| Receive the final unobstructed bounds before a Timeline peek transition.
-}
onWillChange : (Rect -> msg) -> Sub msg
onWillChange =
    Elm.Kernel.PebbleWatch.onUnobstructedWillChange


{-| Receive animation progress while the unobstructed area is changing.

Progress ranges from 0 to 255, matching Pebble's `AnimationProgress`.
-}
onChanging : (Int -> msg) -> Sub msg
onChanging =
    Elm.Kernel.PebbleWatch.onUnobstructedChanging


{-| Receive notification after the unobstructed area finished changing.
-}
onDidChange : msg -> Sub msg
onDidChange =
    Elm.Kernel.PebbleWatch.onUnobstructedDidChange


{-| Read the current unobstructed bounds once.
-}
currentBounds : (Rect -> msg) -> Cmd msg
currentBounds =
    Elm.Kernel.PebbleWatch.unobstructedCurrentBounds
