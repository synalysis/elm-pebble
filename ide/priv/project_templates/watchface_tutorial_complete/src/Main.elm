module Main exposing (main)

import Companion.Types exposing (Location(..), PhoneToWatch(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Events as PebbleEvents
import Pebble.Platform as PebblePlatform
import Pebble.System as PebbleSystem
import Pebble.Time as PebbleTime
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources
import Pebble.Vibes as PebbleVibes


type alias Model =
    { screenW : Int
    , screenH : Int
    , isRound : Bool
    , currentDateTime : Maybe PebbleTime.CurrentDateTime
    , batteryLevel : Maybe Int
    , connected : Maybe Bool
    , temperature : Maybe Temperature
    , condition : Maybe WeatherCondition
    , backgroundColor : Maybe PebbleColor.Color
    , textColor : Maybe PebbleColor.Color
    , showDate : Maybe Bool
    }


type Msg
    = CurrentDateTime PebbleTime.CurrentDateTime
    | FromPhone PhoneToWatch
    | MinuteChanged Int
    | HourChanged Int
    | BatteryLevelChanged Int
    | ConnectionStatusChanged Bool


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { screenW = context.screen.width
      , screenH = context.screen.height
      , isRound = context.screen.isRound
      , currentDateTime = Nothing
      , batteryLevel = Nothing
      , connected = Nothing
      , temperature = Nothing
      , condition = Nothing
      , backgroundColor = Nothing
      , textColor = Nothing
      , showDate = Nothing
      }
    , Cmd.batch
        [ PebbleTime.currentDateTime CurrentDateTime
        , PebbleSystem.batteryLevel BatteryLevelChanged
        , PebbleSystem.connectionStatus ConnectionStatusChanged
        , CompanionWatch.sendWatchToPhone (RequestWeather CurrentLocation)
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model | currentDateTime = Just value }, Cmd.none )

        FromPhone message ->
            updateFromPhone message model

        MinuteChanged minute ->
            ( { model | currentDateTime = updateMinute minute model.currentDateTime }
            , if modBy 30 minute == 0 then
                CompanionWatch.sendWatchToPhone (RequestWeather CurrentLocation)

              else
                Cmd.none
            )

        HourChanged _ ->
            ( model, PebbleTime.currentDateTime CurrentDateTime )

        BatteryLevelChanged level ->
            ( { model | batteryLevel = Just (clamp 0 100 level) }, Cmd.none )

        ConnectionStatusChanged connected ->
            ( { model | connected = Just connected }
            , if connected then
                Cmd.none

              else
                PebbleVibes.doublePulse
            )


updateFromPhone : PhoneToWatch -> Model -> ( Model, Cmd Msg )
updateFromPhone message model =
    case message of
        ProvideTemperature temperature ->
            ( { model | temperature = Just temperature }, Cmd.none )

        ProvideCondition condition ->
            ( { model | condition = Just condition }, Cmd.none )

        SetBackgroundColor color ->
            ( { model | backgroundColor = Just (pebbleColor color) }, Cmd.none )

        SetTextColor color ->
            ( { model | textColor = Just (pebbleColor color) }, Cmd.none )

        SetShowDate value ->
            ( { model | showDate = Just value }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    PebbleEvents.batch
        [ PebbleEvents.onMinuteChange MinuteChanged
        , PebbleEvents.onHourChange HourChanged
        , PebbleSystem.onBatteryChange BatteryLevelChanged
        , PebbleSystem.onConnectionChange ConnectionStatusChanged
        , CompanionWatch.onPhoneToWatch FromPhone
        ]


view : Model -> PebbleUi.UiNode
view model =
    let
        w =
            model.screenW

        h =
            model.screenH

        timeY =
            (h // 2) - 38

        dateY =
            timeY + 48

        weatherY =
            h
                - (if model.isRound then
                    42

                   else
                    32
                  )

        batteryW =
            w // 2

        batteryX =
            (w - batteryW) // 2

        batteryY =
            if model.isRound then
                h // 8

            else
                h // 28

        backgroundColor =
            Maybe.withDefault PebbleColor.black model.backgroundColor

        textColor =
            Maybe.withDefault PebbleColor.white model.textColor

        batteryOps =
            case model.batteryLevel of
                Nothing ->
                    []

                Just batteryLevel ->
                    let
                        batteryFill =
                            ((batteryW - 4) * batteryLevel) // 100

                        batteryColor =
                            if batteryLevel <= 20 then
                                PebbleColor.red

                            else if batteryLevel <= 40 then
                                PebbleColor.chromeYellow

                            else
                                PebbleColor.green
                    in
                    [ PebbleUi.group
                        (PebbleUi.context
                            [ PebbleUi.strokeColor textColor
                            , PebbleUi.fillColor batteryColor
                            , PebbleUi.textColor textColor
                            ]
                            [ PebbleUi.roundRect { x = batteryX, y = batteryY, w = batteryW, h = 8 } 2 textColor
                            , PebbleUi.fillRect { x = batteryX + 2, y = batteryY + 2, w = batteryFill, h = 4 } batteryColor
                            ]
                        )
                    ]

        btIcon =
            case model.connected of
                Just False ->
                    [ PebbleUi.drawBitmapInRect UiResources.BtIcon { x = (w - 30) // 2, y = batteryY + 12, w = 30, h = 30 } ]

                _ ->
                    []

        dateOps =
            case ( model.showDate, model.currentDateTime ) of
                ( Just True, Just currentDateTime ) ->
                    [ drawCentered model textColor dateY 24 (dateString currentDateTime) ]

                _ ->
                    []
    in
    [ PebbleUi.clear backgroundColor
    ]
        ++ batteryOps
        ++ [ drawCentered model textColor timeY 56 (timeString model)
           , drawCentered model textColor weatherY 22 (weatherString model)
           ]
        ++ btIcon
        ++ dateOps
        |> PebbleUi.toUiNode


drawCentered : Model -> PebbleColor.Color -> Int -> Int -> String -> PebbleUi.RenderOp
drawCentered model textColor y height value =
    PebbleUi.group
        (PebbleUi.context
            [ PebbleUi.textColor textColor ]
            [ PebbleUi.text UiResources.Jersey { x = 0, y = y, w = model.screenW, h = height } value ]
        )


timeString : Model -> String
timeString model =
    case model.currentDateTime of
        Nothing ->
            "--:--"

        Just currentDateTime ->
            pad2 currentDateTime.hour ++ ":" ++ pad2 currentDateTime.minute


dateString : PebbleTime.CurrentDateTime -> String
dateString currentDateTime =
    weekdayString currentDateTime.dayOfWeek ++ " " ++ monthString currentDateTime.month ++ " " ++ String.fromInt currentDateTime.day


updateMinute : Int -> Maybe PebbleTime.CurrentDateTime -> Maybe PebbleTime.CurrentDateTime
updateMinute minute maybeCurrentDateTime =
    case maybeCurrentDateTime of
        Nothing ->
            Nothing

        Just currentDateTime ->
            Just { currentDateTime | minute = minute }


weatherString : Model -> String
weatherString model =
    case ( model.temperature, model.condition ) of
        ( Just temperature, Just condition ) ->
            temperatureString temperature ++ " " ++ conditionString condition

        _ ->
            "Loading..."


temperatureString : Temperature -> String
temperatureString temperature =
    case temperature of
        Celsius value ->
            String.fromInt value ++ "C"

        Fahrenheit value ->
            String.fromInt value ++ "F"


pebbleColor : TutorialColor -> PebbleColor.Color
pebbleColor color =
    case color of
        Black ->
            PebbleColor.black

        White ->
            PebbleColor.white

        Green ->
            PebbleColor.green

        Blue ->
            PebbleColor.blue

        Yellow ->
            PebbleColor.chromeYellow


conditionString : WeatherCondition -> String
conditionString condition =
    case condition of
        Clear ->
            "Clear"

        Cloudy ->
            "Cloudy"

        Fog ->
            "Fog"

        Drizzle ->
            "Drizzle"

        Rain ->
            "Rain"

        Snow ->
            "Snow"

        Showers ->
            "Showers"

        Storm ->
            "Storm"

        UnknownWeather ->
            "Weather"


weekdayString : PebbleTime.DayOfWeek -> String
weekdayString day =
    case day of
        PebbleTime.Monday ->
            "Mon"

        PebbleTime.Tuesday ->
            "Tue"

        PebbleTime.Wednesday ->
            "Wed"

        PebbleTime.Thursday ->
            "Thu"

        PebbleTime.Friday ->
            "Fri"

        PebbleTime.Saturday ->
            "Sat"

        PebbleTime.Sunday ->
            "Sun"


monthString : Int -> String
monthString month =
    case month of
        1 ->
            "Jan"

        2 ->
            "Feb"

        3 ->
            "Mar"

        4 ->
            "Apr"

        5 ->
            "May"

        6 ->
            "Jun"

        7 ->
            "Jul"

        8 ->
            "Aug"

        9 ->
            "Sep"

        10 ->
            "Oct"

        11 ->
            "Nov"

        _ ->
            "Dec"


pad2 : Int -> String
pad2 value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    PebblePlatform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
