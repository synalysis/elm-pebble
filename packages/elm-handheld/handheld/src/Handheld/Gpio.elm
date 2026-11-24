module Handheld.Gpio exposing
    ( Level(..)
    , read
    , write
    )

{-| A digital pin.

    import Handheld.Gpio as Gpio exposing (Level(..))

    type Msg
        = Pin Level

    init _ =
        ( model, Gpio.write 1 High )

    update msg model =
        case msg of
            Pin High ->
                ( model, Cmd.none )

            Pin Low ->
                ( model, Cmd.none )

@docs Level, write, read
-}

import Handheld.Raw as Raw


{-| Pin level.
-}
type Level
    = Low
    | High


{-| Drive a pin high or low.
-}
write : Int -> Level -> Cmd msg
write _ _ =
    Raw.none


{-| Read a pin. The message receives `High` or `Low`.
-}
read : Int -> (Level -> msg) -> Cmd msg
read _ _ =
    Raw.none
