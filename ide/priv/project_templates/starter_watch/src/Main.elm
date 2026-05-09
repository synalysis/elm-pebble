module Main exposing (Model, Msg, headOrZero, main, update, view)

{-| Fixture application used by compiler and runtime tests. -}

import Companion.Types exposing (Location(..), Temperature, WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Accel as PebbleAccel
import Pebble.Button as PebbleButton
import Pebble.Cmd
import Pebble.Events as PebbleEvents
import Pebble.Platform as PebblePlatform
import Pebble.Storage as PebbleStorage
import Pebble.Time as PebbleTime
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources
import Pebble.WatchInfo as PebbleWatchInfo


{-| App model with counter and optional temperature. -}
type alias Model =
    { value : Int, temperature : Maybe Temperature }


{-| Messages handled by the fixture update loop. -}
type Msg
    = Increment
    | Decrement
    | Tick Int
    | UpPressed
    | SelectPressed
    | DownPressed
    | AccelTap
    | ProvideTemperature Temperature
    | CurrentTimeString String
    | ClockStyle24h Bool
    | TimezoneIsSet Bool
    | TimezoneName String
    | WatchModelName PebbleWatchInfo.WatchModel
    | WatchColorName PebbleWatchInfo.WatchColor
    | FirmwareVersionString PebbleWatchInfo.FirmwareVersion


{-| Return the first integer in a list, or `0` when empty. -}
headOrZero : List Int -> Int
headOrZero list =
    Maybe.withDefault 0 (List.head list)


helper : Int -> Int
helper value =
    value + 2


advanced : Int -> Int
advanced n =
    let base = helper n in if base > 10 then base else base + 1


counterOf : Model -> Int
counterOf model =
    model.value


temperatureOf : Model -> Maybe Temperature
temperatureOf model =
    model.temperature


requestWeather : Location -> Cmd Msg
requestWeather location =
    CompanionWatch.sendWatchToPhone (RequestWeather location)


requestSystemInfo : Cmd Msg
requestSystemInfo =
    Cmd.batch
        [ PebbleTime.currentTimeString CurrentTimeString
        , PebbleTime.clockStyle24h ClockStyle24h
        , PebbleTime.timezoneIsSet TimezoneIsSet
        , PebbleTime.timezone TimezoneName
        , PebbleWatchInfo.getModel WatchModelName
        , PebbleWatchInfo.getColor WatchColorName
        , PebbleWatchInfo.getFirmwareVersion FirmwareVersionString
        ]


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init launchContext =
    let
        initial =
            PebblePlatform.launchReasonToInt launchContext.reason
    in
    ( { value = initial, temperature = Nothing }
    , Cmd.batch [ requestWeather Berlin, requestSystemInfo ]
    )


{-| Update the model with an incoming message. -}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            handlePlatformMsg msg model

        UpPressed ->
            handlePlatformMsg msg model

        SelectPressed ->
            handlePlatformMsg msg model

        DownPressed ->
            handlePlatformMsg msg model

        AccelTap ->
            handlePlatformMsg msg model

        _ ->
            handleAppMsg msg model


handleAppMsg : Msg -> Model -> ( Model, Cmd Msg )
handleAppMsg msg model =
    case msg of
        Increment ->
            let counter = counterOf model in ( { value = counter + 1, temperature = temperatureOf model }, Cmd.none )

        Decrement ->
            let counter = counterOf model in ( { value = counter - 1, temperature = temperatureOf model }, Cmd.none )

        ProvideTemperature temperature ->
            ( { value = counterOf model, temperature = Just temperature }, Cmd.none )

        CurrentTimeString _ ->
            ( model, Cmd.none )

        ClockStyle24h _ ->
            ( model, Cmd.none )

        TimezoneIsSet _ ->
            ( model, Cmd.none )

        TimezoneName _ ->
            ( model, Cmd.none )

        WatchModelName _ ->
            ( model, Cmd.none )

        WatchColorName _ ->
            ( model, Cmd.none )

        FirmwareVersionString _ ->
            ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


handlePlatformMsg : Msg -> Model -> ( Model, Cmd Msg )
handlePlatformMsg msg model =
    case msg of
        Tick _ ->
            let counter = counterOf model in let next = advanced counter in ( { value = next, temperature = temperatureOf model }, Pebble.Cmd.timerAfter 1000 )

        UpPressed ->
            let counter = counterOf model in let next = counter + 1 in ( { value = next, temperature = temperatureOf model }, PebbleStorage.writeInt 1 next )

        SelectPressed ->
            ( model, Cmd.batch [ requestWeather Berlin, requestSystemInfo ] )

        DownPressed ->
            let counter = counterOf model in ( { value = counter - 1, temperature = temperatureOf model }, PebbleStorage.delete 1 )

        AccelTap ->
            let counter = counterOf model in ( { value = counter + 1, temperature = temperatureOf model }, Cmd.none )

        _ ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    PebbleEvents.batch [ PebbleEvents.onTick Tick, PebbleButton.onPress PebbleButton.Up UpPressed, PebbleButton.onPress PebbleButton.Select SelectPressed, PebbleButton.onPress PebbleButton.Down DownPressed, PebbleAccel.onTap AccelTap ]


{-| Produce the retained virtual UI tree for rendering. -}
view : Model -> PebbleUi.UiNode
view model =
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.group
                    (PebbleUi.context
                        [ PebbleUi.strokeWidth 3
                        , PebbleUi.antialiased 1
                        , PebbleUi.strokeColor PebbleColor.black
                        , PebbleUi.fillColor PebbleColor.black
                        , PebbleUi.textColor PebbleColor.black
                        ]
                        [ PebbleUi.roundRect { x = 6, y = 6, w = 132, h = 70 } 6 PebbleColor.black
                        , PebbleUi.arc { x = 20, y = 16, w = 36, h = 36 } 0 45000
                        , PebbleUi.pathOutline
                            (PebbleUi.path
                                [ { x = 0, y = 0 }, { x = 10, y = 4 }, { x = 16, y = 14 }, { x = 8, y = 24 }, { x = 0, y = 18 } ]
                                { x = 86, y = 16 }
                                (PebbleUi.rotationFromPebbleAngle 0)
                            )
                        , PebbleUi.pathFilled
                            (PebbleUi.path
                                [ { x = 0, y = 0 }, { x = 8, y = 6 }, { x = 6, y = 14 }, { x = 2, y = 20 }, { x = 0, y = 14 } ]
                                { x = 108, y = 26 }
                                (PebbleUi.rotationFromPebbleAngle 0)
                            )
                        , PebbleUi.pathOutlineOpen
                            (PebbleUi.path
                                [ { x = 0, y = 0 }, { x = 8, y = 4 }, { x = 16, y = 2 }, { x = 24, y = 6 } ]
                                { x = 10, y = 78 }
                                (PebbleUi.rotationFromPebbleAngle 0)
                            )
                        ]
                    )
                , PebbleUi.line { x = 0, y = 84 } { x = 143, y = 84 } PebbleColor.black
                , PebbleUi.pixel { x = 72, y = 84 } PebbleColor.black
                , statusDraw model
                , counterDraw model
                ]
            ]
        ]


statusDraw : Model -> PebbleUi.RenderOp
statusDraw model =
    let maybeTemp = temperatureOf model in
    case maybeTemp of
        Just temperature ->
            PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 28 } (temperatureValue temperature)

        Nothing ->
            PebbleUi.textLabel UiResources.DefaultFont { x = 0, y = 28 } PebbleUi.WaitingForCompanion


counterDraw : Model -> PebbleUi.RenderOp
counterDraw model =
    let counter = counterOf model in PebbleUi.textInt UiResources.DefaultFont { x = 0, y = 56 } counter


temperatureValue : Temperature -> Int
temperatureValue temperature =
    case temperature of
        Celsius value ->
            value

        Fahrenheit value ->
            value


{-| Program entry point. -}
main : Program Decode.Value Model Msg
main =
    PebblePlatform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
