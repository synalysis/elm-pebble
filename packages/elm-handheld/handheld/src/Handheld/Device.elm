module Handheld.Device exposing
    ( Module(..)
    , ready
    )

{-| Optional hardware.

A module is absent on some devices. USB is present on MeowKit and absent on
Flipper Zero. Ask before using it.

    import Handheld.Device as Device exposing (Module(..))

    type Msg
        = UsbReady Bool

    init _ =
        ( model, Device.ready Usb UsbReady )

    update msg model =
        case msg of
            UsbReady True ->
                ( model, Handheld.Usb.tap Handheld.Usb.enter )

            UsbReady False ->
                ( model, Cmd.none )

@docs Module, ready
-}

import Handheld.Raw as Raw


{-| A host module that may be missing.
-}
type Module
    = Nfc
    | Infrared
    | Gpio
    | Usb
    | Radio
    | Sensors


{-| Ask whether a module is present. The message receives `True` or `False`.
-}
ready : Module -> (Bool -> msg) -> Cmd msg
ready _ _ =
    Raw.none
