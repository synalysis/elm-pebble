module Pebble.Platform exposing
    ( LaunchContext
    , LaunchReason(..)
    , LaunchScreen
    , ColorCapability(..)
    , DisplayShape(..)
    , application
    , colorCapabilityIsColor
    , displayShapeIsRound
    , launchReasonFromTag
    , launchReasonToInt
    , watchface
    )

{-| Platform glue for Pebble watch applications.

This module wraps `Platform.worker` so your `init` function receives a
typed `LaunchContext` decoded from JSON launch metadata.

# Launch metadata
@docs LaunchReason, LaunchScreen, LaunchContext, ColorCapability, DisplayShape, launchReasonFromTag, launchReasonToInt, colorCapabilityIsColor, displayShapeIsRound

# Program entrypoint
@docs watchface, application

-}

import Platform
import Json.Decode as Decode


{-| Why the app or worker launched on the watch.
-}
type LaunchReason
    = LaunchSystem
    | LaunchUser
    | LaunchPhone
    | LaunchWakeup
    | LaunchWorker
    | LaunchQuickLaunch
    | LaunchTimelineAction
    | LaunchSmartstrap
    | LaunchUnknown


{-| Display shape for the currently simulated or connected watch model.
-}
type DisplayShape
    = Rectangular
    | Round


{-| Color capability for the currently simulated or connected watch model.
-}
type ColorCapability
    = BlackWhite
    | Color


{-| Encode a `LaunchReason` into the integer tag used by the native runtime.
-}
launchReasonToInt : LaunchReason -> Int
launchReasonToInt launchReason =
    case launchReason of
        LaunchSystem ->
            0

        LaunchUser ->
            1

        LaunchPhone ->
            2

        LaunchWakeup ->
            3

        LaunchWorker ->
            4

        LaunchQuickLaunch ->
            5

        LaunchTimelineAction ->
            6

        LaunchSmartstrap ->
            7

        LaunchUnknown ->
            -1


{-| Screen details for the currently simulated or connected watch model.
-}
type alias LaunchScreen =
    { width : Int
    , height : Int
    , shape : DisplayShape
    , colorMode : ColorCapability
    }


{-| Full launch metadata delivered to `init`.
-}
type alias LaunchContext =
    { reason : LaunchReason
    , watchModel : String
    , watchProfileId : String
    , screen : LaunchScreen
    , hasMicrophone : Bool
    , hasCompass : Bool
    , supportsHealth : Bool
    }


{-| Decode an integer launch tag into a `LaunchReason`.
-}
launchReasonFromTag : Int -> LaunchReason
launchReasonFromTag tag =
    if tag == 0 then
        LaunchSystem
    else if tag == 1 then
        LaunchUser
    else if tag == 2 then
        LaunchPhone
    else if tag == 3 then
        LaunchWakeup
    else if tag == 4 then
        LaunchWorker
    else if tag == 5 then
        LaunchQuickLaunch
    else if tag == 6 then
        LaunchTimelineAction
    else if tag == 7 then
        LaunchSmartstrap
    else
        LaunchUnknown


launchReasonFromString : String -> LaunchReason
launchReasonFromString value =
    if value == "LaunchSystem" then
        LaunchSystem
    else if value == "LaunchUser" then
        LaunchUser
    else if value == "LaunchPhone" then
        LaunchPhone
    else if value == "LaunchWakeup" then
        LaunchWakeup
    else if value == "LaunchWorker" then
        LaunchWorker
    else if value == "LaunchQuickLaunch" then
        LaunchQuickLaunch
    else if value == "LaunchTimelineAction" then
        LaunchTimelineAction
    else if value == "LaunchSmartstrap" then
        LaunchSmartstrap
    else
        LaunchUnknown


displayShapeFromString : String -> DisplayShape
displayShapeFromString value =
    if value == "Round" || value == "round" then
        Round
    else
        Rectangular


colorCapabilityFromString : String -> ColorCapability
colorCapabilityFromString value =
    if value == "Color" || value == "color" then
        Color
    else
        BlackWhite


{-| Whether a display shape is round.
-}
displayShapeIsRound : DisplayShape -> Bool
displayShapeIsRound shape =
    case shape of
        Round ->
            True

        Rectangular ->
            False


{-| Whether a color capability supports color rendering.
-}
colorCapabilityIsColor : ColorCapability -> Bool
colorCapabilityIsColor colorMode =
    case colorMode of
        Color ->
            True

        BlackWhite ->
            False


defaultScreen : LaunchScreen
defaultScreen =
    { width = 144
    , height = 168
    , shape = Rectangular
    , colorMode = Color
    }


defaultContext : LaunchContext
defaultContext =
    { reason = LaunchUser
    , watchModel = "Pebble Time Steel"
    , watchProfileId = "basalt"
    , screen = defaultScreen
    , hasMicrophone = False
    , hasCompass = False
    , supportsHealth = True
    }


decodeFieldWithDefault : String -> Decoder a -> a -> Decoder a
decodeFieldWithDefault name decoder fallback =
    Decode.oneOf
        [ Decode.field name decoder
        , Decode.succeed fallback
        ]


type alias Decoder a =
    Decode.Decoder a


launchReasonDecoder : Decoder LaunchReason
launchReasonDecoder =
    Decode.map launchReasonFromString Decode.string


displayShapeDecoder : Decoder DisplayShape
displayShapeDecoder =
    Decode.oneOf
        [ Decode.map displayShapeFromString Decode.string
        , Decode.map (\isRound -> if isRound then Round else Rectangular) Decode.bool
        ]


colorCapabilityDecoder : Decoder ColorCapability
colorCapabilityDecoder =
    Decode.oneOf
        [ Decode.map colorCapabilityFromString Decode.string
        , Decode.map (\isColor -> if isColor then Color else BlackWhite) Decode.bool
        ]


screenDecoder : Decoder LaunchScreen
screenDecoder =
    Decode.map4
        (\width height shape colorMode ->
            { width = width
            , height = height
            , shape = shape
            , colorMode = colorMode
            }
        )
        (decodeFieldWithDefault "width" Decode.int defaultScreen.width)
        (decodeFieldWithDefault "height" Decode.int defaultScreen.height)
        (Decode.oneOf
            [ decodeFieldWithDefault "shape" displayShapeDecoder defaultScreen.shape
            , Decode.map
                (\legacyShape ->
                    if legacyShape == "round" then
                        Round
                    else
                        Rectangular
                )
                (decodeFieldWithDefault "shape" Decode.string "rect")
            ]
        )
        (Decode.oneOf
            [ decodeFieldWithDefault "color_mode" colorCapabilityDecoder defaultScreen.colorMode
            , decodeFieldWithDefault "colorMode" colorCapabilityDecoder defaultScreen.colorMode
            , Decode.map
                (\isColor ->
                    if isColor then
                        Color
                    else
                        BlackWhite
                )
                (decodeFieldWithDefault "is_color" Decode.bool (colorCapabilityIsColor defaultScreen.colorMode))
            ]
        )


contextObjectDecoder : Decoder LaunchContext
contextObjectDecoder =
    Decode.map7
        (\reason watchModel watchProfileId screen hasMicrophone hasCompass supportsHealth ->
            { reason = reason
            , watchModel = watchModel
            , watchProfileId = watchProfileId
            , screen = screen
            , hasMicrophone = hasMicrophone
            , hasCompass = hasCompass
            , supportsHealth = supportsHealth
            }
        )
        (Decode.oneOf
            [ decodeFieldWithDefault "launch_reason" launchReasonDecoder defaultContext.reason
            , decodeFieldWithDefault "reason" launchReasonDecoder defaultContext.reason
            ]
        )
        (Decode.oneOf
            [ decodeFieldWithDefault "watch_model" Decode.string defaultContext.watchModel
            , decodeFieldWithDefault "watchModel" Decode.string defaultContext.watchModel
            ]
        )
        (Decode.oneOf
            [ decodeFieldWithDefault "watch_profile_id" Decode.string defaultContext.watchProfileId
            , decodeFieldWithDefault "watchProfileId" Decode.string defaultContext.watchProfileId
            ]
        )
        (decodeFieldWithDefault "screen" screenDecoder defaultContext.screen)
        (Decode.oneOf
            [ decodeFieldWithDefault "has_microphone" Decode.bool defaultContext.hasMicrophone
            , decodeFieldWithDefault "hasMicrophone" Decode.bool defaultContext.hasMicrophone
            ]
        )
        (Decode.oneOf
            [ decodeFieldWithDefault "has_compass" Decode.bool defaultContext.hasCompass
            , decodeFieldWithDefault "hasCompass" Decode.bool defaultContext.hasCompass
            ]
        )
        (Decode.oneOf
            [ decodeFieldWithDefault "supports_health" Decode.bool defaultContext.supportsHealth
            , decodeFieldWithDefault "supportsHealth" Decode.bool defaultContext.supportsHealth
            ]
        )


launchContextDecoder : Decoder LaunchContext
launchContextDecoder =
    contextObjectDecoder


decodeLaunchContext : Decode.Value -> LaunchContext
decodeLaunchContext flags =
    case Decode.decodeValue launchContextDecoder flags of
        Ok context ->
            context

        Err _ ->
            defaultContext


{-| Start a Pebble watchface.

`config.init` receives a typed launch context. `view` is retained as the
watch rendering contract, while init/update/subscriptions are forwarded to
Elm's headless `Platform.worker`.
-}
watchface :
    { init : LaunchContext -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> view
    , subscriptions : model -> Sub msg
    }
    -> Program Decode.Value model msg
watchface config =
    application config


{-| Start a Pebble watch application.

Use this for apps rather than watchfaces. It currently has the same runtime
shape as `watchface`, but keeps the app/watchface distinction explicit for
build tooling.
-}
application :
    { init : LaunchContext -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , view : model -> view
    , subscriptions : model -> Sub msg
    }
    -> Program Decode.Value model msg
application config =
    Platform.worker
        { init = \flags -> config.init (decodeLaunchContext flags)
        , update = config.update
        , subscriptions = config.subscriptions
        }
