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
import Yes.Layout as Layout
import Yes.Render as Render


type alias SunWindow =
    Render.SunWindow


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
    { layout : Layout.Layout
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
    , lastSunFetchDayKey : Maybe Int
    , lastWeatherFetchHourKey : Maybe Int
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
            { layout = Layout.fromScreen context.screen.width context.screen.height
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
            , lastSunFetchDayKey = Nothing
            , lastWeatherFetchHourKey = Nothing
            }
    in
    ( model
    , Cmd.batch
        [ Time.currentDateTime CurrentDateTime
        , System.batteryLevel BatteryLevelChanged
        , System.connectionStatus ConnectionChanged
        , Health.supported GotHealthSupported
        , CompanionWatch.sendWatchToPhone RequestSunData
        , CompanionWatch.sendWatchToPhone RequestWeather
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            let
                modelWithTime =
                    { model | now = Just value }

                dayKey =
                    calendarDayKey value

                hourKey =
                    calendarHourKey value
            in
            if model.lastSunFetchDayKey == Nothing && model.lastWeatherFetchHourKey == Nothing then
                ( { modelWithTime
                    | lastSunFetchDayKey = Just dayKey
                    , lastWeatherFetchHourKey = Just hourKey
                  }
                , Cmd.none
                )

            else
                scheduleCompanionFetches modelWithTime Cmd.none

        MinuteChanged minute ->
            case model.now of
                Nothing ->
                    ( model, Time.currentDateTime CurrentDateTime )

                Just now ->
                    scheduleCompanionFetches
                        { model | now = Just { now | minute = minute } }
                        (refreshStepsIfSupported model)

        HourChanged _ ->
            scheduleCompanionFetches model (Time.currentDateTime CurrentDateTime)

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


scheduleCompanionFetches : Model -> Cmd Msg -> ( Model, Cmd Msg )
scheduleCompanionFetches model extraCmd =
    case model.now of
        Nothing ->
            ( model, extraCmd )

        Just now ->
            let
                dayKey =
                    calendarDayKey now

                hourKey =
                    calendarHourKey now

                needsSun =
                    model.lastSunFetchDayKey /= Just dayKey

                needsWeather =
                    model.lastWeatherFetchHourKey /= Just hourKey

                sunCmd =
                    if needsSun then
                        CompanionWatch.sendWatchToPhone RequestSunData

                    else
                        Cmd.none

                weatherCmd =
                    if needsWeather then
                        CompanionWatch.sendWatchToPhone RequestWeather

                    else
                        Cmd.none

                nextModel =
                    { model
                        | lastSunFetchDayKey =
                            if needsSun then
                                Just dayKey

                            else
                                model.lastSunFetchDayKey
                        , lastWeatherFetchHourKey =
                            if needsWeather then
                                Just hourKey

                            else
                                model.lastWeatherFetchHourKey
                    }
            in
            ( nextModel, Cmd.batch [ extraCmd, sunCmd, weatherCmd ] )


calendarDayKey : Time.CurrentDateTime -> Int
calendarDayKey now =
    now.year * 10000 + now.month * 100 + now.day


calendarHourKey : Time.CurrentDateTime -> Int
calendarHourKey now =
    calendarDayKey now * 100 + now.hour


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
    Render.face model.layout (faceDisplay model)


faceDisplay : Model -> Render.FaceDisplay
faceDisplay model =
    { showCorners = showCorners model
    , homeMinute = homeMinuteOfDay model
    , timeText = timeString model
    , sun = model.sun
    , moonPhaseE6 = model.moonPhaseE6
    , corners = cornerSlots model
    }


cornerSlots : Model -> Render.CornerSlots
cornerSlots model =
    { topLeft = topLeftSlot model
    , date = dateSlot model
    , weather = weatherSlot model
    , bottomRight = bottomRightSlot model
    }


topLeftSlot : Model -> { value : String, caption : String }
topLeftSlot model =
    case pickTopLeft model of
        BatteryCorner ->
            { value = batteryPercentString model, caption = "Battery" }

        StepsCorner ->
            { value = stepsString model, caption = "Steps" }


dateSlot : Model -> Maybe String
dateSlot model =
    case model.now of
        Nothing ->
            Nothing

        Just now ->
            Just (monthString now.month ++ " " ++ String.fromInt now.day)


weatherSlot : Model -> Maybe String
weatherSlot model =
    Maybe.map (weatherLabel model) (pickWeatherMode model)


bottomRightSlot : Model -> Render.BottomRightSlot
bottomRightSlot model =
    case pickBottomRight model of
        AltitudeCorner ->
            case model.altitude of
                Just altitude ->
                    Render.AltitudeSlot (altitudeString altitude)

                Nothing ->
                    Render.SimpleLine "--"

        SunCorner ->
            sunBottomRightSlot model

        MoonCorner ->
            moonBottomRightSlot model


sunBottomRightSlot : Model -> Render.BottomRightSlot
sunBottomRightSlot model =
    case Maybe.map .mode model.sun of
        Just PolarDay ->
            Render.SimpleLine "Sun day"

        Just PolarNight ->
            Render.SimpleLine "Sun night"

        _ ->
            case nextSunCountdown (homeMinuteOfDay model) model.sun of
                Nothing ->
                    Render.SimpleLine "--"

                Just ( label, timeLine ) ->
                    Render.CountdownSlot label timeLine


moonBottomRightSlot : Model -> Render.BottomRightSlot
moonBottomRightSlot model =
    case ( model.moonriseMin, model.moonsetMin ) of
        ( Nothing, Nothing ) ->
            Render.SimpleLine "--"

        _ ->
            case nextMoonCountdown (homeMinuteOfDay model) model.moonriseMin model.moonsetMin of
                Nothing ->
                    Render.SimpleLine "--"

                Just ( label, timeLine ) ->
                    Render.CountdownSlot label timeLine


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


homeMinuteOfDay : Model -> Int
homeMinuteOfDay model =
    case model.now of
        Nothing ->
            720

        Just now ->
            modBy 1440 ((now.hour * 60) + now.minute + model.homeTzOffsetMin - now.utcOffsetMinutes)


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


minutesUntilCircular : Int -> Int -> Int
minutesUntilCircular fromMinute toMinute =
    modBy 1440 (toMinute - fromMinute + 1440)


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
