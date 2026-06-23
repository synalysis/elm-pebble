module Pebble.AppFocus exposing (State(..), onChange)

{-| Observe when the watch app gains or loses foreground focus.

Subscribe once and update your model when the user leaves or returns to your app.

    import Pebble.AppFocus as AppFocus

    type Msg
        = FocusChanged AppFocus.State

    subscriptions _ =
        AppFocus.onChange FocusChanged

    update msg model =
        case msg of
            FocusChanged AppFocus.InFocus ->
                ( { model | paused = False }, Cmd.none )

            FocusChanged AppFocus.OutOfFocus ->
                ( { model | paused = True }, Cmd.none )

For a runnable example, use the **watch-demo-app-focus** project template in the IDE.

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
