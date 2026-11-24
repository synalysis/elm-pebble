module Handheld.Platform exposing
    ( Device(..)
    , LaunchContext
    , LaunchScreen
    , application
    )

{-| Program entry for a MeowKit or Flipper app.

`init` receives a `LaunchContext` with the device, panel size, color depth,
and whether the panel accepts touch. Match `device` directly:

    case context.device of
        MeowKit ->
            "color"

        FlipperZero ->
            "mono"

There is no companion app and no protocol interface. `update` and
`subscriptions` run on the device. `view` returns draw commands.

@docs Device, LaunchScreen, LaunchContext, application
-}

import Json.Decode as Decode exposing (Decoder)
import Platform


{-| Which handheld started the app.
-}
type Device
    = MeowKit
    | FlipperZero


{-| Width, height, and bits per pixel. Depth `1` is mono. Depth `16` is color.
-}
type alias LaunchScreen =
    { width : Int
    , height : Int
    , colorDepth : Int
    }


{-| Facts the host knows before the first frame.
-}
type alias LaunchContext =
    { device : Device
    , screen : LaunchScreen
    , touch : Bool
    }


application :
    { init : LaunchContext -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> Cmd msg
    , subscriptions : model -> Sub msg
    }
    -> Program Decode.Value model msg
application config =
    Platform.worker
        { init = \flags -> config.init (decodeLaunchContext flags)
        , update = config.update
        , subscriptions = config.subscriptions
        }


decodeLaunchContext : Decode.Value -> LaunchContext
decodeLaunchContext flags =
    case Decode.decodeValue launchContextDecoder flags of
        Ok context ->
            context

        Err _ ->
            { device = MeowKit
            , screen = { width = 320, height = 240, colorDepth = 16 }
            , touch = True
            }


launchContextDecoder : Decoder LaunchContext
launchContextDecoder =
    Decode.map3 LaunchContext
        (Decode.oneOf
            [ Decode.field "device" deviceDecoder
            , Decode.succeed MeowKit
            ]
        )
        (Decode.field "screen" screenDecoder)
        (Decode.oneOf
            [ Decode.field "touch" Decode.bool
            , Decode.succeed True
            ]
        )


screenDecoder : Decoder LaunchScreen
screenDecoder =
    Decode.map3 LaunchScreen
        (Decode.field "width" Decode.int)
        (Decode.field "height" Decode.int)
        (Decode.field "colorDepth" Decode.int)


deviceDecoder : Decoder Device
deviceDecoder =
    Decode.string
        |> Decode.andThen
            (\name ->
                if name == "flipper-zero" || name == "FlipperZero" then
                    Decode.succeed FlipperZero

                else if name == "meowkit" || name == "MeowKit" then
                    Decode.succeed MeowKit

                else
                    Decode.fail ("Unknown handheld " ++ name)
            )
