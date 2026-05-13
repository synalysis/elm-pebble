module Main exposing (main)

import Companion.Types exposing (AltitudeUnit(..), InternetMode(..), PhoneToWatch(..), SunMode(..), TemperatureUnit(..), TideKind(..), WatchToPhone(..), WeatherCondition(..), WindUnit(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.System as System
import Pebble.Time as Time
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias DisplayUnits =
    { temperature : TemperatureUnit
    , wind : WindUnit
    }


type alias SunWindow =
    { sunriseMin : Int
    , sunsetMin : Int
    , mode : SunMode
    }


type alias Temperature =
    { c10 : Int
    , unit : TemperatureUnit
    }


type WindDirection
    = North
    | NorthEast
    | East
    | SouthEast
    | South
    | SouthWest
    | West
    | NorthWest


type alias Wind =
    { direction : WindDirection
    , speed : Int
    , unit : WindUnit
    }


type alias Weather =
    { temperature : Temperature
    , condition : WeatherCondition
    , precipMm10 : Int
    , uv10 : Int
    , pressureHpa : Int
    }


type alias Tide =
    { nextMin : Int
    , levelCm : Int
    , progress : Int
    , kind : TideKind
    }


type alias Altitude =
    { meters : Int
    , unit : AltitudeUnit
    }


type alias Model =
    { screenW : Int
    , screenH : Int
    , isRound : Bool
    , now : Maybe Time.CurrentDateTime
    , tickSecond : Int
    , batteryLevel : Maybe Int
    , connected : Maybe Bool
    , homeLatE6 : Maybe Int
    , homeLonE6 : Maybe Int
    , homeTzOffsetMin : Int
    , displayUnits : DisplayUnits
    , sun : Maybe SunWindow
    , moonriseMin : Maybe Int
    , moonsetMin : Maybe Int
    , moonPhaseE6 : Maybe Int
    , weather : Maybe Weather
    , wind : Maybe Wind
    , tide : Maybe Tide
    , altitude : Maybe Altitude
    , internetMode : InternetMode
    }


type Msg
    = CurrentDateTime Time.CurrentDateTime
    | MinuteChanged Int
    | HourChanged Int
    | SecondChanged Int
    | BatteryLevelChanged Int
    | ConnectionChanged Bool
    | FromPhone PhoneToWatch
    | RequestRefresh


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { screenW = context.screen.width
      , screenH = context.screen.height
      , isRound = context.screen.isRound
      , now = Nothing
      , tickSecond = 0
      , batteryLevel = Nothing
      , connected = Nothing
      , homeLatE6 = Nothing
      , homeLonE6 = Nothing
      , homeTzOffsetMin = 0
      , displayUnits = { temperature = Celsius, wind = MetersPerSecond }
      , sun = Nothing
      , moonriseMin = Nothing
      , moonsetMin = Nothing
      , moonPhaseE6 = Nothing
      , weather = Nothing
      , wind = Nothing
      , tide = Nothing
      , altitude = Nothing
      , internetMode = InternetEnabled
      }
    , Cmd.batch
        [ Time.currentDateTime CurrentDateTime
        , System.batteryLevel BatteryLevelChanged
        , System.connectionStatus ConnectionChanged
        , CompanionWatch.sendWatchToPhone RequestUpdate
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model | now = Just value }, Cmd.none )

        MinuteChanged minute ->
            ( { model | now = Maybe.map (\now -> { now | minute = minute }) model.now }
            , CompanionWatch.sendWatchToPhone RequestUpdate
            )

        HourChanged _ ->
            ( model, Time.currentDateTime CurrentDateTime )

        SecondChanged second ->
            ( { model | tickSecond = second }, Cmd.none )

        BatteryLevelChanged level ->
            ( { model | batteryLevel = Just (clamp 0 100 level) }, Cmd.none )

        ConnectionChanged connected ->
            ( { model | connected = Just connected }, Cmd.none )

        RequestRefresh ->
            ( model, CompanionWatch.sendWatchToPhone RequestUpdate )

        FromPhone message ->
            ( updateFromPhone message model, Cmd.none )


updateFromPhone : PhoneToWatch -> Model -> Model
updateFromPhone message model =
    case message of
        ProvideLocation lat lon offset ->
            { model | homeLatE6 = Just lat, homeLonE6 = Just lon, homeTzOffsetMin = offset }

        ProvideSun sunrise sunset sunMode ->
            { model | sun = Just { sunriseMin = sunrise, sunsetMin = sunset, mode = sunMode } }

        ProvideMoon moonrise moonset phase ->
            { model | moonriseMin = Just moonrise, moonsetMin = Just moonset, moonPhaseE6 = Just phase }

        ProvideMoonPhase phase ->
            { model | moonPhaseE6 = Just phase }

        ProvideWeather temp condition precip uv pressure tempUnit ->
            { model
                | weather =
                    Just
                        { temperature = { c10 = temp, unit = tempUnit }
                        , condition = condition
                        , precipMm10 = precip
                        , uv10 = uv
                        , pressureHpa = pressure
                        }
                , displayUnits = updateTemperatureUnit tempUnit model.displayUnits
            }

        ProvideWind windDir windSpeed windUnit ->
            { model
                | wind =
                    Just
                        { direction = windDirectionFromSector windDir
                        , speed = windSpeed
                        , unit = windUnit
                        }
                , displayUnits = updateWindUnit windUnit model.displayUnits
            }

        ProvideTide nextMin levelCm progress tideKind ->
            { model
                | tide =
                    Just
                        { nextMin = nextMin
                        , levelCm = levelCm
                        , progress = clamp 0 1000 progress
                        , kind = tideKind
                        }
            }

        ClearTide ->
            { model | tide = Nothing }

        ProvideAltitude meters unit ->
            { model | altitude = Just { meters = meters, unit = unit } }

        SetUseInternet mode ->
            { model | internetMode = mode }

        SetUnits tempUnit windUnit ->
            { model
                | displayUnits = { temperature = tempUnit, wind = windUnit }
                , weather = Maybe.map (mapWeatherTemperatureUnit tempUnit) model.weather
                , wind = Maybe.map (mapWindUnit windUnit) model.wind
            }


updateTemperatureUnit : TemperatureUnit -> DisplayUnits -> DisplayUnits
updateTemperatureUnit unit units =
    { units | temperature = unit }


updateWindUnit : WindUnit -> DisplayUnits -> DisplayUnits
updateWindUnit unit units =
    { units | wind = unit }


mapWeatherTemperatureUnit : TemperatureUnit -> Weather -> Weather
mapWeatherTemperatureUnit unit weather =
    { weather | temperature = { c10 = weather.temperature.c10, unit = unit } }


mapWindUnit : WindUnit -> Wind -> Wind
mapWindUnit unit wind =
    { wind | unit = unit }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Events.onMinuteChange MinuteChanged
        , Events.onHourChange HourChanged
        , Events.onSecondChange SecondChanged
        , System.onBatteryChange BatteryLevelChanged
        , System.onConnectionChange ConnectionChanged
        , CompanionWatch.onPhoneToWatch FromPhone
        , Button.onRelease Button.Down RequestRefresh
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode (faceOps model)


faceOps : Model -> List Ui.RenderOp
faceOps model =
    let
        cx =
            model.screenW // 2

        cy =
            model.screenH // 2

        radius =
            (min model.screenW model.screenH // 2) - 8

        dial =
            drawDial model cx cy radius

        corners =
            if model.isRound then
                []

            else
                drawCorners model

        date =
            if model.isRound then
                []

            else
                drawDate model
    in
    [ Ui.clear Color.black ]
        ++ dial
        ++ date
        ++ corners


drawDial : Model -> Int -> Int -> Int -> List Ui.RenderOp
drawDial model cx cy radius =
    let
        nowMin =
            homeMinuteOfDay model

        sunWindow =
            Maybe.withDefault defaultSunWindow model.sun

        sunrise =
            sunWindow.sunriseMin

        sunset =
            sunWindow.sunsetMin

        moonrise =
            Maybe.withDefault 0 model.moonriseMin

        moonset =
            Maybe.withDefault 720 model.moonsetMin

        phase =
            Maybe.withDefault (fallbackMoonPhaseE6 model) model.moonPhaseE6

        dayText =
            if isDayAtTop model then
                Color.black

            else
                Color.white

        hand =
            pointAt cx cy (radius - 10) (angleFromMinute nowMin)

        moonPhaseY =
            cy + (radius // 2)

        timeTextY =
            cy - (radius // 2) - 9
    in
    [ Ui.fillCircle { x = cx, y = cy } radius Color.oxfordBlue
    , Ui.group
        (Ui.context
            [ Ui.fillColor Color.blueMoon, Ui.strokeColor Color.blueMoon ]
            [ Ui.fillRadial (square cx cy (radius - 3)) (angleFromMinute moonrise) (angleFromMinute moonset) ]
        )
    , Ui.fillCircle { x = cx, y = cy } (radius - 10) Color.black
    , Ui.group
        (Ui.context
            [ Ui.fillColor Color.chromeYellow, Ui.strokeColor Color.chromeYellow ]
            [ if sunWindow.mode == PolarDay then
                Ui.fillCircle { x = cx, y = cy } (radius - 18) Color.chromeYellow

              else
                Ui.fillRadial (square cx cy (radius - 18)) (angleFromMinute sunrise) (angleFromMinute sunset)
            ]
        )
    , Ui.circle { x = cx, y = cy } radius Color.white
    , Ui.circle { x = cx, y = cy } (radius - 10) Color.darkGray
    ]
        ++ drawOuterScale cx cy radius
        ++ drawMoonPhase cx moonPhaseY (max 10 (radius // 5)) phase
        ++ [ Ui.line { x = cx, y = cy } hand Color.white
           , Ui.fillCircle { x = cx, y = cy } 4 Color.white
           , textAt dayText { x = cx - 31, y = timeTextY, w = 64, h = 18 } (timeString model)
           ]


drawOuterScale : Int -> Int -> Int -> List Ui.RenderOp
drawOuterScale cx cy radius =
    List.concatMap
        (\hour ->
            let
                outer =
                    pointAt cx cy radius (angleFromMinute (hour * 60))

                inner =
                    pointAt cx cy
                        (radius
                            - (if modBy 2 hour == 0 then
                                7

                               else
                                4
                              )
                        )
                        (angleFromMinute (hour * 60))

                labelPoint =
                    pointAt cx cy (radius - 17) (angleFromMinute (hour * 60))

                label =
                    if hour == 0 then
                        "24"

                    else
                        String.fromInt hour
            in
            if modBy 2 hour == 0 then
                [ Ui.line outer inner Color.white
                , textAt Color.lightGray { x = Tuple.first labelPoint - 7, y = Tuple.second labelPoint - 5, w = 18, h = 10 } label
                ]

            else
                [ Ui.line outer inner Color.lightGray ]
        )
        (List.range 0 23)


drawMoonPhase : Int -> Int -> Int -> Int -> List Ui.RenderOp
drawMoonPhase cx cy radius phaseE6 =
    let
        lit =
            abs (phaseE6 - 500000) * radius // 500000

        offset =
            if phaseE6 < 500000 then
                -lit

            else
                lit
    in
    [ Ui.fillCircle { x = cx, y = cy } radius Color.lightGray
    , Ui.fillCircle { x = cx + offset, y = cy } radius Color.black
    , Ui.circle { x = cx, y = cy } radius Color.white
    ]


drawDate : Model -> List Ui.RenderOp
drawDate model =
    case model.now of
        Nothing ->
            []

        Just now ->
            [ textAt Color.white { x = model.screenW - 52, y = 4, w = 48, h = 14 } (monthString now.month ++ " " ++ String.fromInt now.day)
            , textAt Color.lightGray { x = model.screenW - 42, y = 18, w = 38, h = 12 } (String.fromInt now.year)
            ]


drawCorners : Model -> List Ui.RenderOp
drawCorners model =
    [ drawTopLeft model
    , drawWeatherCorner model
    , drawBottomRight model
    ]
        |> List.concat


drawTopLeft : Model -> List Ui.RenderOp
drawTopLeft model =
    case model.connected of
        Just False ->
            [ textAt Color.red { x = 4, y = 4, w = 32, h = 18 } "BT" ]

        _ ->
            let
                showBattery =
                    batteryAlert model && slot model 2 == 1

                label =
                    if showBattery then
                        String.fromInt (Maybe.withDefault 0 model.batteryLevel) ++ "%"

                    else
                        "--"
            in
            [ textAt Color.white { x = 4, y = 4, w = 40, h = 16 } label
            , textAt Color.darkGray { x = 4, y = 18, w = 44, h = 12 } (if showBattery then "Battery" else "Steps")
            ]


drawWeatherCorner : Model -> List Ui.RenderOp
drawWeatherCorner model =
    let
        y =
            model.screenH - 36

        mode =
            slot model 5

        label =
            if mode == 0 then
                temperatureString model

            else if mode == 1 then
                windString model

            else if mode == 2 then
                precipitationString model

            else if mode == 3 then
                uvString model

            else
                pressureString model

        condition =
            model.weather
                |> Maybe.map .condition
                |> Maybe.withDefault UnknownWeather
    in
    drawWeatherIcon 8 (y - 18) condition
        ++ [ textAt Color.white { x = 4, y = y, w = 68, h = 18 } label ]


drawBottomRight : Model -> List Ui.RenderOp
drawBottomRight model =
    let
        x =
            model.screenW - 64

        y =
            model.screenH - 36
    in
    case model.tide of
        Just tide ->
            drawTide x (y - 8) model tide

        Nothing ->
            case model.altitude of
                Just altitude ->
                    [ mountainIcon (x + 3) (y - 12)
                    , textAt Color.white { x = x, y = y, w = 60, h = 18 } (altitudeString altitude)
                    ]

                Nothing ->
                    drawSunMoonCountdown x y model


drawTide : Int -> Int -> Model -> Tide -> List Ui.RenderOp
drawTide x y model tide =
    let
        highLow =
            if tide.kind == HighTide then
                "H"

            else
                "L"

        mode =
            slot model 3
    in
    [ Ui.circle { x = x + 48, y = y + 10 } 11 Color.blueMoon
    , Ui.arc (square (x + 48) (y + 10) 10) 0 (tide.progress * 65536 // 1000)
    , textAt Color.white { x = x, y = y, w = 60, h = 18 } (tideLabel tide mode highLow)
    ]


tideLabel : Tide -> Int -> String -> String
tideLabel tide mode highLow =
    if mode == 0 then
        highLow ++ " " ++ durationString tide.nextMin

    else if mode == 1 then
        decimal1 (abs tide.levelCm) ++ "m"

    else if tide.kind == HighTide then
        "Rising"

    else
        "Falling"


drawSunMoonCountdown : Int -> Int -> Model -> List Ui.RenderOp
drawSunMoonCountdown x y model =
    let
        nowMin =
            homeMinuteOfDay model

        mode =
            slot model 3

        label =
            if mode == 0 then
                nextEventString nowMin "SR" "SS" (Maybe.map .sunriseMin model.sun) (Maybe.map .sunsetMin model.sun)

            else if mode == 1 then
                nextEventString nowMin "MR" "MS" model.moonriseMin model.moonsetMin

            else
                "Age " ++ decimal1 (moonAge10 model)
    in
    [ textAt Color.white { x = x, y = y, w = 62, h = 18 } label ]


drawWeatherIcon : Int -> Int -> WeatherCondition -> List Ui.RenderOp
drawWeatherIcon x y condition =
    case condition of
        Clear ->
            [ Ui.fillCircle { x = x + 12, y = y + 12 } 8 Color.chromeYellow ]

        Cloudy ->
            cloudIcon x y

        Fog ->
            [ Ui.line { x = x + 2, y = y + 8 } { x = x + 24, y = y + 8 } Color.lightGray
            , Ui.line { x = x + 4, y = y + 14 } { x = x + 26, y = y + 14 } Color.lightGray
            ]

        Drizzle ->
            cloudIcon x y ++ rainLines x y 2

        Rain ->
            cloudIcon x y ++ rainLines x y 3

        Showers ->
            cloudIcon x y ++ rainLines x y 4

        Snow ->
            cloudIcon x y ++ [ textAt Color.white { x = x + 9, y = y + 14, w = 16, h = 12 } "*" ]

        Storm ->
            cloudIcon x y ++ [ Ui.line { x = x + 13, y = y + 12 } { x = x + 8, y = y + 23 } Color.chromeYellow, Ui.line { x = x + 8, y = y + 23 } { x = x + 18, y = y + 17 } Color.chromeYellow ]

        UnknownWeather ->
            [ Ui.circle { x = x + 12, y = y + 12 } 8 Color.darkGray ]


cloudIcon : Int -> Int -> List Ui.RenderOp
cloudIcon x y =
    [ Ui.fillCircle { x = x + 10, y = y + 12 } 7 Color.lightGray
    , Ui.fillCircle { x = x + 18, y = y + 13 } 6 Color.lightGray
    , Ui.fillRect { x = x + 6, y = y + 12, w = 18, h = 8 } Color.lightGray
    ]


rainLines : Int -> Int -> Int -> List Ui.RenderOp
rainLines x y count =
    List.map
        (\index ->
            let
                dx =
                    x + 7 + (index * 5)
            in
            Ui.line { x = dx, y = y + 22 } { x = dx - 2, y = y + 27 } Color.blueMoon
        )
        (List.range 0 (count - 1))


mountainIcon : Int -> Int -> Ui.RenderOp
mountainIcon x y =
    Ui.pathOutlineOpen
        (Ui.path
            [ { x = x, y = y + 18 }, { x = x + 10, y = y + 4 }, { x = x + 18, y = y + 18 }, { x = x + 26, y = y + 7 }, { x = x + 34, y = y + 18 } ]
            { x = 0, y = 0 }
            (Ui.rotationFromDegrees 0)
        )


textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAt color bounds value =
    Ui.group
        (Ui.context
            [ Ui.textColor color ]
            [ Ui.text Resources.DefaultFont bounds value ]
        )


pointAt : Int -> Int -> Int -> Int -> Ui.Point
pointAt cx cy radius angle =
    let
        theta =
            toFloat angle * 2 * Basics.pi / 65536
    in
    { x = cx + round (sin theta * toFloat radius)
    , y = cy - round (cos theta * toFloat radius)
    }


square : Int -> Int -> Int -> Ui.Rect
square cx cy radius =
    { x = cx - radius, y = cy - radius, w = radius * 2, h = radius * 2 }


angleFromMinute : Int -> Int
angleFromMinute minute =
    modBy 65536 (((minute - 720) * 65536) // 1440)


homeMinuteOfDay : Model -> Int
homeMinuteOfDay model =
    case model.now of
        Nothing ->
            720

        Just now ->
            modBy 1440 ((now.hour * 60) + now.minute + model.homeTzOffsetMin - now.utcOffsetMinutes)


defaultSunWindow : SunWindow
defaultSunWindow =
    { sunriseMin = 360
    , sunsetMin = 1080
    , mode = SunCycle
    }


isDayAtTop : Model -> Bool
isDayAtTop model =
    let
        sunWindow =
            Maybe.withDefault defaultSunWindow model.sun

        sunrise =
            sunWindow.sunriseMin

        sunset =
            sunWindow.sunsetMin
    in
    sunWindow.mode == PolarDay || (sunrise <= 720 && 720 <= sunset)


timeString : Model -> String
timeString model =
    let
        minute =
            homeMinuteOfDay model

        hour =
            minute // 60
    in
    pad2 hour ++ ":" ++ pad2 (modBy 60 minute)


temperatureString : Model -> String
temperatureString model =
    case Maybe.map .temperature model.weather of
        Nothing ->
            "--"

        Just temperature ->
            if temperature.unit == Fahrenheit then
                String.fromInt ((temperature.c10 * 9 // 5 + 320 + 5) // 10) ++ "F"

            else
                String.fromInt ((temperature.c10 + 5) // 10) ++ "C"


windString : Model -> String
windString model =
    case model.wind of
        Nothing ->
            "--"

        Just wind ->
            directionString wind.direction ++ " " ++ String.fromInt wind.speed ++ windUnitString wind.unit


precipitationString : Model -> String
precipitationString model =
    case model.weather of
        Nothing ->
            "--"

        Just weather ->
            if weather.temperature.unit == Fahrenheit then
                decimal1 (weather.precipMm10 * 4 // 10) ++ "in"

            else
                decimal1 weather.precipMm10 ++ "mm"


uvString : Model -> String
uvString model =
    case model.weather of
        Nothing ->
            "UV --"

        Just weather ->
            "UV " ++ decimal1 weather.uv10


pressureString : Model -> String
pressureString model =
    case model.weather of
        Nothing ->
            "--"

        Just weather ->
            String.fromInt weather.pressureHpa ++ "hPa"


windUnitString : WindUnit -> String
windUnitString unit =
    if unit == MilesPerHour then
        "mph"

    else
        "m/s"


altitudeString : Altitude -> String
altitudeString altitude =
    if altitude.unit == Feet then
        String.fromInt (altitude.meters * 328 // 100) ++ "ft"

    else
        String.fromInt altitude.meters ++ "m"


nextEventString : Int -> String -> String -> Maybe Int -> Maybe Int -> String
nextEventString nowMin riseLabel setLabel maybeRise maybeSet =
    case ( maybeRise, maybeSet ) of
        ( Just rise, Just set ) ->
            if nowMin < rise then
                riseLabel ++ " " ++ durationString (rise - nowMin)

            else if nowMin < set then
                setLabel ++ " " ++ durationString (set - nowMin)

            else
                riseLabel ++ " " ++ durationString (rise + 1440 - nowMin)

        _ ->
            "--"


durationString : Int -> String
durationString minutes =
    String.fromInt (minutes // 60) ++ ":" ++ pad2 (modBy 60 minutes)


moonAge10 : Model -> Int
moonAge10 model =
    Maybe.withDefault (fallbackMoonPhaseE6 model) model.moonPhaseE6 * 295 // 1000000


fallbackMoonPhaseE6 : Model -> Int
fallbackMoonPhaseE6 model =
    case model.now of
        Nothing ->
            0

        Just now ->
            modBy 1000000 (((now.day + (now.month * 29)) * 33898) + (now.minute * 23))


batteryAlert : Model -> Bool
batteryAlert model =
    case model.batteryLevel of
        Just level ->
            level <= 25

        Nothing ->
            False


slot : Model -> Int -> Int
slot model count =
    modBy count (model.tickSecond // 5)


windDirectionFromSector : Int -> WindDirection
windDirectionFromSector sector =
    case modBy 8 sector of
        0 ->
            North

        1 ->
            NorthEast

        2 ->
            East

        3 ->
            SouthEast

        4 ->
            South

        5 ->
            SouthWest

        6 ->
            West

        _ ->
            NorthWest


directionString : WindDirection -> String
directionString direction =
    case direction of
        North ->
            "N"

        NorthEast ->
            "NE"

        East ->
            "E"

        SouthEast ->
            "SE"

        South ->
            "S"

        SouthWest ->
            "SW"

        West ->
            "W"

        NorthWest ->
            "NW"


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


decimal1 : Int -> String
decimal1 value =
    let
        sign =
            if value < 0 then
                "-"

            else
                ""

        absolute =
            abs value
    in
    sign ++ String.fromInt (absolute // 10) ++ "." ++ String.fromInt (modBy 10 absolute)


pad2 : Int -> String
pad2 value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
