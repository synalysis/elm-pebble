module Main exposing (main)

import Companion.Types exposing (Altitude(..), PhoneToWatch(..), SunMode(..), Temperature(..), TideKind(..), WatchToPhone(..), WeatherCondition(..), WindDirection(..), WindSpeed(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import List
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Health as Health
import Pebble.Platform as Platform
import Pebble.System as System
import Pebble.Time as Time
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias SunWindow =
    { sunriseMin : Int
    , sunsetMin : Int
    , mode : SunMode
    }


type alias Weather =
    { temperature : Temperature
    , condition : WeatherCondition
    , precipMm10 : Int
    , uv10 : Int
    , pressureHpa : Int
    }


type alias Wind =
    { direction : WindDirection
    , speed : WindSpeed
    }


type alias Tide =
    { nextMin : Int
    , levelCm : Int
    , progress : Int
    , kind : TideKind
    }


type alias Model =
    { screenW : Int
    , screenH : Int
    , displayShape : Platform.DisplayShape
    , now : Maybe Time.CurrentDateTime
    , cornerCycle : Int
    , batteryLevel : Maybe Int
    , connected : Maybe Bool
    , homeTzOffsetMin : Int
    , sun : Maybe SunWindow
    , moonriseMin : Maybe Int
    , moonsetMin : Maybe Int
    , moonPhaseE6 : Maybe Int
    , weather : Maybe Weather
    , wind : Maybe Wind
    , tide : Maybe Tide
    , altitude : Maybe Altitude
    , cornerUpdateIntervalSec : Int
    , healthSupported : Maybe Bool
    , stepsToday : Maybe Int
    }


type Msg
    = CurrentDateTime Time.CurrentDateTime
    | MinuteChanged Int
    | HourChanged Int
    | SecondChanged Int
    | BatteryLevelChanged Int
    | ConnectionChanged Bool
    | GotHealthSupported Bool
    | GotStepsToday Int
    | HealthEvent Health.Event
    | FromPhone PhoneToWatch
    | RequestRefresh


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    let
        model =
            { screenW = context.screen.width
            , screenH = context.screen.height
            , displayShape = context.screen.shape
            , now = Nothing
            , cornerCycle = 0
            , batteryLevel = Nothing
            , connected = Nothing
            , homeTzOffsetMin = 0
            , sun = Nothing
            , moonriseMin = Nothing
            , moonsetMin = Nothing
            , moonPhaseE6 = Nothing
            , weather = Nothing
            , wind = Nothing
            , tide = Nothing
            , altitude = Nothing
            , cornerUpdateIntervalSec = 5
            , healthSupported = Nothing
            , stepsToday = Nothing
            }
    in
    ( model
    , Cmd.batch
        [ Time.currentDateTime CurrentDateTime
        , System.batteryLevel BatteryLevelChanged
        , System.connectionStatus ConnectionChanged
        , Health.supported GotHealthSupported
        , CompanionWatch.sendWatchToPhone RequestUpdate
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model | now = Just value }, Cmd.none )

        MinuteChanged minute ->
            case model.now of
                Nothing ->
                    ( model, Time.currentDateTime CurrentDateTime )

                Just now ->
                    ( { model | now = Just { now | minute = minute } }
                    , Cmd.batch
                        [ CompanionWatch.sendWatchToPhone RequestUpdate
                        , refreshStepsIfSupported model
                        ]
                    )

        HourChanged _ ->
            ( model, Time.currentDateTime CurrentDateTime )

        SecondChanged second ->
            if shouldRefreshCorners model second then
                let
                    nextModel =
                        if showCorners model then
                            { model | cornerCycle = model.cornerCycle + 1 }

                        else
                            model
                in
                ( nextModel, Cmd.none )

            else
                ( model, Cmd.none )

        BatteryLevelChanged level ->
            ( { model | batteryLevel = Just (clamp 0 100 level) }, Cmd.none )

        ConnectionChanged connected ->
            ( { model | connected = Just connected }, Cmd.none )

        GotHealthSupported supported ->
            ( { model | healthSupported = Just supported }
            , if supported then
                  Health.sumToday Health.StepCount GotStepsToday

              else
                  Cmd.none
            )

        GotStepsToday steps ->
            ( { model | stepsToday = Just steps }, Cmd.none )

        HealthEvent _ ->
            ( model, refreshStepsIfSupported model )

        RequestRefresh ->
            ( model, CompanionWatch.sendWatchToPhone RequestUpdate )

        FromPhone message ->
            ( updateFromPhone message model, Cmd.none )


updateFromPhone : PhoneToWatch -> Model -> Model
updateFromPhone message model =
    case message of
        ProvideTimezone offset ->
            { model | homeTzOffsetMin = offset }

        ProvideSun sunrise sunset sunMode ->
            { model | sun = Just { sunriseMin = sunrise, sunsetMin = sunset, mode = sunMode } }

        ProvideMoon moonrise moonset phase ->
            { model
                | moonriseMin = eventMinuteFromPayload moonrise moonset moonrise
                , moonsetMin = eventMinuteFromPayload moonrise moonset moonset
                , moonPhaseE6 = Just phase
            }

        ProvideMoonPhase phase ->
            { model | moonPhaseE6 = Just phase }

        ProvideWeather temperature condition precip uv pressure ->
            { model
                | weather =
                    Just
                        { temperature = temperature
                        , condition = condition
                        , precipMm10 = precip
                        , uv10 = uv
                        , pressureHpa = pressure
                        }
            }

        ProvideWind direction windSpeed ->
            { model
                | wind =
                    Just
                        { direction = direction
                        , speed = windSpeed
                        }
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

        ProvideAltitude altitude ->
            { model | altitude = Just altitude }

        SetCornerUpdateInterval seconds ->
            { model | cornerUpdateIntervalSec = normalizeCycleSec seconds }


refreshStepsIfSupported : Model -> Cmd Msg
refreshStepsIfSupported model =
    case model.healthSupported of
        Just True ->
            Health.sumToday Health.StepCount GotStepsToday

        _ ->
            Cmd.none


shouldRefreshCorners : Model -> Int -> Bool
shouldRefreshCorners model second =
    modBy (normalizeCycleSec model.cornerUpdateIntervalSec) second == 0


showCorners : Model -> Bool
showCorners model =
    not (Platform.displayShapeIsRound model.displayShape)
        && model.sun
        /= Nothing


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        healthSub =
            case model.healthSupported of
                Just True ->
                    Health.onEvent HealthEvent

                _ ->
                    Sub.none
    in
    Events.batch
        [ Events.onMinuteChange MinuteChanged
        , Events.onHourChange HourChanged
        , Events.onSecondChange SecondChanged
        , System.onBatteryChange BatteryLevelChanged
        , System.onConnectionChange ConnectionChanged
        , CompanionWatch.onPhoneToWatch FromPhone
        , Button.onRelease Button.Down RequestRefresh
        , healthSub
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
            (min model.screenW model.screenH // 2) - 22

        dial =
            drawDial model cx cy radius
    in
    [ Ui.clear Color.black ]
        ++ dial
        ++ (if showCorners model then
                drawCorners model

            else
                []
           )


drawDial : Model -> Int -> Int -> Int -> List Ui.RenderOp
drawDial model cx cy radius =
    let
        nowMin =
            homeMinuteOfDay model

        sunWindow =
            Maybe.withDefault defaultSunWindow model.sun

        hasSunData =
            case model.sun of
                Just _ ->
                    True

                Nothing ->
                    False

        sunrise =
            sunWindow.sunriseMin

        sunset =
            sunWindow.sunsetMin

        timeTextColor =
            Color.black

        moonPhaseY =
            cy + (min model.screenW model.screenH // 5)

        timeTextY =
            cy - (radius // 2) - 9

        sunriseAngle =
            angleFromMinute sunrise

        sunsetAngle =
            angleFromMinute sunset

        moonStart =
            sunriseAngle

        moonEnd =
            sunsetAngle

        moonBounds =
            square cx cy radius

        sunBounds =
            square cx cy (radius - 5)
    in
    [ Ui.fillCircle { x = cx, y = cy } radius Color.oxfordBlue ]
        ++ (if hasSunData then
                [ Ui.group
                    (Ui.context
                        [ Ui.fillColor Color.blueMoon, Ui.strokeColor Color.blueMoon ]
                        [ Ui.fillRadial moonBounds
                            moonStart
                            (if moonEnd < moonStart then
                                65536

                             else
                                moonEnd
                            )
                        ]
                    )
                ]
                    ++ (if moonEnd < moonStart then
                            [ Ui.group
                                (Ui.context
                                    [ Ui.fillColor Color.blueMoon, Ui.strokeColor Color.blueMoon ]
                                    [ Ui.fillRadial moonBounds 0 moonEnd ]
                                )
                            ]

                        else
                            []
                       )

            else
                []
           )
        ++ [ Ui.fillCircle { x = cx, y = cy } (radius - 5) Color.black ]
        ++ drawSunWindow { x = cx, y = cy } (radius - 5) sunBounds sunriseAngle sunsetAngle sunWindow
        ++ [ Ui.circle { x = cx, y = cy } radius Color.white
           , Ui.circle { x = cx, y = cy } (radius - 5) Color.darkGray
           ]
        ++ drawOuterScale cx cy radius
        ++ (case model.moonPhaseE6 of
                Just phase ->
                    drawMoonPhase cx moonPhaseY (max 10 (radius // 5)) phase

                Nothing ->
                    []
           )
        ++ draw24HourHand cx cy radius nowMin moonPhaseY
        ++ [ textAt timeTextColor { x = cx - 31, y = timeTextY, w = 64, h = 18 } (timeString model)
           ]


draw24HourHand : Int -> Int -> Int -> Int -> Int -> List Ui.RenderOp
draw24HourHand cx cy radius nowMin moonCy =
    let
        handAngle =
            angleFromMinute nowMin

        hubR =
            max 4 (radius * 6 // 50)

        moonRingR =
            max 8 (radius * 10 // 50)

        handLen =
            radius - max 10 (radius * 18 // 50)

        tip =
            pointAt cx cy handLen handAngle
    in
    [ Ui.fillCircle { x = cx, y = moonCy } moonRingR Color.black
    , Ui.circle { x = cx, y = moonCy } moonRingR Color.white
    , Ui.line { x = cx, y = cy } tip Color.white
    , Ui.fillCircle { x = cx, y = cy } hubR Color.black
    , Ui.circle { x = cx, y = cy } hubR Color.white
    ]


drawOuterScale : Int -> Int -> Int -> List Ui.RenderOp
drawOuterScale cx cy radius =
    List.map
        (\hour ->
            let
                angle =
                    angleFromMinute (hour * 120)

                inner =
                    pointAt cx cy radius angle

                outer =
                    pointAt cx cy (radius + 6) angle
            in
            Ui.line outer inner Color.white
        )
        (List.range 0 11)


drawSunWindow : Ui.Point -> Int -> Ui.Rect -> Int -> Int -> SunWindow -> List Ui.RenderOp
drawSunWindow center radius bounds sunriseAngle sunsetAngle sunWindow =
    case sunWindow.mode of
        PolarNight ->
            []

        PolarDay ->
            [ Ui.fillCircle center radius Color.chromeYellow ]

        SunCycle ->
            [ Ui.fillRadial bounds sunriseAngle sunsetAngle ]


drawMoonPhase : Int -> Int -> Int -> Int -> List Ui.RenderOp
drawMoonPhase cx cy radius _ phaseE6 =
    [ Ui.fillCircle { x = cx, y = cy } radius Color.lightGray
    , Ui.circle { x = cx, y = cy } radius Color.white
    ]


drawDate : Model -> List Ui.RenderOp
drawDate model =
    case model.now of
        Nothing ->
            []

        Just now ->
            let
                pad =
                    cornerPad model
            in
            [ textAt Color.white { x = model.screenW - 52, y = pad, w = 48, h = 14 } (monthString now.month ++ " " ++ String.fromInt now.day)
            ]


drawCorners : Model -> List Ui.RenderOp
drawCorners model =
    [ drawTopLeft model
    , drawDate model
    , drawWeatherCorner model
    , drawBottomRight model
    ]
        |> List.concat


type alias SlotSpec id =
    { id : id
    , available : Bool
    , exclusive : Bool
    }


pickSlot : Model -> List (SlotSpec id) -> Maybe id
pickSlot model slots =
    case List.filter (\slot -> slot.exclusive && slot.available) slots |> List.head of
        Just slot ->
            Just slot.id

        Nothing ->
            pickFromCycledList model (List.filter .available slots |> List.map .id)


pickFromCycledList : Model -> List a -> Maybe a
pickFromCycledList model items =
    case items of
        [] ->
            Nothing

        _ ->
            items
                |> List.drop (cycleSlot model (List.length items))
                |> List.head


type TopLeftCorner
    = BatteryCorner
    | StepsCorner


type WeatherCornerMode
    = TempCorner
    | WindCorner


type BottomRightCorner
    = AltitudeCorner
    | SunCorner
    | MoonCorner


drawTopLeft : Model -> List Ui.RenderOp
drawTopLeft model =
    let
        pad =
            cornerPad model
    in
    case pickTopLeft model of
        BatteryCorner ->
            [ textAt Color.white { x = pad, y = pad, w = 40, h = 16 } (batteryPercentString model)
            , textAt Color.darkGray { x = pad, y = pad + 16, w = 44, h = 12 } "Battery"
            ]

        StepsCorner ->
            [ textAt Color.white { x = pad, y = pad, w = 40, h = 16 } (stepsString model)
            , textAt Color.darkGray { x = pad, y = pad + 16, w = 44, h = 12 } "Steps"
            ]


pickTopLeft : Model -> TopLeftCorner
pickTopLeft model =
    case pickSlot model (topLeftSlots model) of
        Just corner ->
            corner

        Nothing ->
            BatteryCorner


topLeftSlots : Model -> List (SlotSpec TopLeftCorner)
topLeftSlots model =
    [ { id = BatteryCorner, available = topLeftBatteryAvailable model, exclusive = False }
    , { id = StepsCorner, available = topLeftStepsAvailable model, exclusive = False }
    ]


topLeftBatteryAvailable : Model -> Bool
topLeftBatteryAvailable model =
    model.connected /= Just False && (batteryAlert model || not (haveSteps model))


topLeftStepsAvailable : Model -> Bool
topLeftStepsAvailable model =
    model.connected == Just True && haveSteps model


drawWeatherCorner : Model -> List Ui.RenderOp
drawWeatherCorner model =
    case pickWeatherMode model of
        Nothing ->
            []

        Just mode ->
            let
                pad =
                    cornerPad model

                cornerBottom =
                    model.screenH - pad

                textH =
                    14

                textTop =
                    cornerBottom - textH

                label =
                    weatherLabel model mode
            in
            [ textAt Color.white { x = pad, y = textTop, w = model.screenW // 2 - pad, h = textH } label ]


pickWeatherMode : Model -> Maybe WeatherCornerMode
pickWeatherMode model =
    pickFromCycledList model (availableWeatherModes model)


availableWeatherModes : Model -> List WeatherCornerMode
availableWeatherModes model =
    case model.weather of
        Nothing ->
            []

        Just _ ->
            List.filterMap identity
                [ Just TempCorner
                , if hasWind model then
                      Just WindCorner

                  else
                      Nothing
                ]


weatherLabel : Model -> WeatherCornerMode -> String
weatherLabel model mode =
    case mode of
        TempCorner ->
            temperatureString model

        WindCorner ->
            windString model


hasWind : Model -> Bool
hasWind model =
    case model.wind of
        Nothing ->
            False

        Just wind ->
            wind.speed /= 0


                drawBottomRight : Model -> List Ui.RenderOp


drawBottomRight model =
    let
        pad =
            cornerPad model

        x =
            model.screenW - 64

        bottom =
            model.screenH - pad
    in
    case pickBottomRight model of
        AltitudeCorner ->
            case model.altitude of
                Just altitude ->
                    [ Ui.drawVectorAt Resources.VectorStaticMountain { x = x + 3, y = bottom - 38 }
                    , textAt Color.white { x = x, y = bottom - 14, w = 60, h = 14 } (altitudeString altitude)
                    ]

                Nothing ->
                    []

        SunCorner ->
            drawSunCountdown x bottom model

        MoonCorner ->
            drawMoonCountdown x bottom model


pickBottomRight : Model -> BottomRightCorner
pickBottomRight model =
    Maybe.withDefault SunCorner (pickSlot model (bottomRightSlots model))


bottomRightSlots : Model -> List (SlotSpec BottomRightCorner)
bottomRightSlots model =
    [ { id = AltitudeCorner, available = model.altitude /= Nothing, exclusive = False }
    , { id = SunCorner, available = model.sun /= Nothing, exclusive = False }
    , { id = MoonCorner, available = hasMoonTimes model, exclusive = False }
    ]


hasMoonTimes : Model -> Bool
hasMoonTimes model =
    model.moonriseMin /= Nothing || model.moonsetMin /= Nothing


drawSunCountdown : Int -> Int -> Model -> List Ui.RenderOp
drawSunCountdown x bottom model =
    case Maybe.map .mode model.sun of
        Just PolarDay ->
            [ textAt Color.white { x = x, y = bottom - 14, w = 62, h = 14 } "Sun day" ]

        Just PolarNight ->
            [ textAt Color.white { x = x, y = bottom - 14, w = 62, h = 14 } "Sun night" ]

        _ ->
            case nextSunCountdown (homeMinuteOfDay model) model.sun of
                Nothing ->
                    [ textAt Color.white { x = x, y = bottom - 14, w = 62, h = 14 } "--" ]

                Just ( label, timeLine ) ->
                    drawBottomRightCountdown x bottom label timeLine


drawMoonCountdown : Int -> Int -> Model -> List Ui.RenderOp
drawMoonCountdown x bottom model =
    case ( model.moonriseMin, model.moonsetMin ) of
        ( Nothing, Nothing ) ->
            [ textAt Color.white { x = x, y = bottom - 14, w = 62, h = 14 } "--" ]

        _ ->
            case nextMoonCountdown (homeMinuteOfDay model) model.moonriseMin model.moonsetMin of
                Nothing ->
                    [ textAt Color.white { x = x, y = bottom - 14, w = 62, h = 14 } "--" ]

                Just ( label, timeLine ) ->
                    drawBottomRightCountdown x bottom label timeLine


drawBottomRightCountdown : Int -> Int -> String -> String -> List Ui.RenderOp
drawBottomRightCountdown x bottom label timeLine =
    let
        labelH =
            12

        timeH =
            14

        topY =
            bottom - labelH - timeH

        labelY =
            topY - 2
    in
    [ textAt Color.lightGray { x = x, y = labelY, w = 62, h = labelH } label
    , textAt Color.white { x = x, y = topY + labelH - 1, w = 62, h = timeH } timeLine
    ]


cornerPad : Model -> Int
cornerPad model =
    max 4 (min model.screenW model.screenH // 36)


nextMoonEventString : Int -> Maybe Int -> Maybe Int -> String
nextMoonEventString nowMin maybeRise maybeSet =
    case ( maybeRise, maybeSet ) of
        ( Just rise, Just set ) ->
            let
                toRise =
                    minutesUntilCircular nowMin rise

                toSet =
                    minutesUntilCircular nowMin set
            in
            if toRise <= toSet then
                "MR " ++ durationString toRise

            else
                "MS " ++ durationString toSet

        _ ->
            "--"


minutesUntilCircular : Int -> Int -> Int
minutesUntilCircular fromMinute toMinute =
    modBy 1440 (toMinute - fromMinute + 1440)


drawWeatherIcon : Int -> Int -> WeatherCondition -> List Ui.RenderOp
drawWeatherIcon x y condition =
    [ Ui.drawVectorAt (conditionVector condition) { x = x, y = y } ]


conditionVector : WeatherCondition -> Resources.StaticVector
conditionVector condition =
    case condition of
        Clear ->
            Resources.VectorStaticWeatherClear

        Cloudy ->
            Resources.VectorStaticWeatherCloudy

        Fog ->
            Resources.VectorStaticWeatherFog

        Drizzle ->
            Resources.VectorStaticWeatherDrizzle

        Rain ->
            Resources.VectorStaticWeatherRain

        Snow ->
            Resources.VectorStaticWeatherSnow

        Showers ->
            Resources.VectorStaticWeatherShowers

        Storm ->
            Resources.VectorStaticWeatherStorm

        UnknownWeather ->
            Resources.VectorStaticWeatherUnknown


textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAt color bounds value =
    Ui.group
        (Ui.context
            [ Ui.textColor color ]
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
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


eventMinuteFromPayload : Int -> Int -> Int -> Maybe Int
eventMinuteFromPayload rise set value =
    if rise == 0 && set == 0 then
        Nothing

    else
        Just value


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

        Just (Celsius c10) ->
            String.fromInt ((c10 + 5) // 10) ++ "C"

        Just (Fahrenheit f10) ->
            String.fromInt ((f10 + 5) // 10) ++ "F"


windString : Model -> String
windString model =
    case model.wind of
        Nothing ->
            "--"

        Just wind ->
            directionString wind.direction
                ++ " "
                ++ windSpeedString wind.speed


windSpeedString : WindSpeed -> String
windSpeedString speed =
    case speed of
        MetersPerSecond value ->
            String.fromInt value ++ "m/s"

        MilesPerHour value ->
            String.fromInt value ++ "mph"


altitudeString : Altitude -> String
altitudeString altitude =
    case altitude of
        Meters meters ->
            String.fromInt meters ++ "m"

        Feet feet ->
            String.fromInt feet ++ "ft"


nextEventString : Int -> String -> String -> Maybe Int -> Maybe Int -> String
nextEventString nowMin riseLabel setLabel maybeRise maybeSet =
    case nextEventParts nowMin riseLabel setLabel maybeRise maybeSet of
        Nothing ->
            "--"

        Just ( label, timeLine ) ->
            label ++ " " ++ timeLine


nextSunCountdown : Int -> Maybe SunWindow -> Maybe ( String, String )
nextSunCountdown nowMin maybeSun =
    case maybeSun of
        Nothing ->
            Nothing

        Just sun ->
            nextEventParts nowMin "SR" "SS" (Just sun.sunriseMin) (Just sun.sunsetMin)


nextMoonCountdown : Int -> Maybe Int -> Maybe Int -> Maybe ( String, String )
nextMoonCountdown nowMin maybeRise maybeSet =
    case ( maybeRise, maybeSet ) of
        ( Just rise, Just set ) ->
            let
                toRise =
                    minutesUntilCircular nowMin rise

                toSet =
                    minutesUntilCircular nowMin set
            in
            if toRise <= toSet then
                Just ( "MR", durationString toRise )

            else
                Just ( "MS", durationString toSet )

        _ ->
            Nothing


nextEventParts : Int -> String -> String -> Maybe Int -> Maybe Int -> Maybe ( String, String )
nextEventParts nowMin riseLabel setLabel maybeRise maybeSet =
    case ( maybeRise, maybeSet ) of
        ( Just rise, Just set ) ->
            if nowMin < rise then
                Just ( riseLabel, durationString (rise - nowMin) )

            else if nowMin < set then
                Just ( setLabel, durationString (set - nowMin) )

            else
                Just ( riseLabel, durationString (rise + 1440 - nowMin) )

        _ ->
            Nothing


durationString : Int -> String
durationString minutes =
    String.fromInt (minutes // 60) ++ ":" ++ pad2 (modBy 60 minutes)


batteryAlert : Model -> Bool
batteryAlert model =
    case model.batteryLevel of
        Just level ->
            level <= 25

                Nothing ->
            False


haveSteps : Model -> Bool
haveSteps model =
    case model.stepsToday of
        Just steps ->
            steps > 0

        Nothing ->
            False


batteryPercentString : Model -> String
batteryPercentString model =
    String.fromInt (Maybe.withDefault 0 model.batteryLevel) ++ "%"


stepsString : Model -> String
stepsString model =
    case model.stepsToday of
        Nothing ->
            "--"

        Just steps ->
            if steps >= 10000 then
                String.fromInt (steps // 1000) ++ "k"

            else
                String.fromInt steps


normalizeCycleSec : Int -> Int
normalizeCycleSec seconds =
    if seconds == 10 || seconds == 30 || seconds == 60 then
        seconds

    else
        5


cycleSlot : Model -> Int -> Int
cycleSlot model count =
    modBy count model.cornerCycle


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
