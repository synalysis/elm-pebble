module CompanionApp exposing (main)

import Companion.GeneratedPreferences as GeneratedPreferences
import Companion.Types exposing (PhoneToWatch(..), SunMode(..), Temperature(..), TideKind(..), WatchToPhone(..), WeatherCondition(..), WindDirection(..), WindSpeed(..))
import CompanionPreferences
import Json.Decode as Decode
import Pebble.Companion.Environment as Environment
import Pebble.Companion.Geolocation as Geolocation
import Pebble.Companion.Phone as CompanionPhone
import Pebble.Companion.Weather as Weather
import Platform
import Task
import Time


type alias Model =
    { settings : Maybe CompanionPreferences.Settings
    , lastLocation : Maybe LocationSnapshot
    , errors : List String
    }


type alias Flags =
    Decode.Value


type alias LocationSnapshot =
    Geolocation.Location


type Msg
    = FromWatch (Result String WatchToPhone)
    | FromConfiguration (Result String CompanionPreferences.Settings)
    | CurrentPosition (Result String LocationSnapshot)
    | CurrentTime LocationSnapshot Time.Posix
    | GotWeather (Result String Weather.WeatherUpdate)
    | GotEnvironment (Result String Environment.EnvironmentInfo)


init : Flags -> ( Model, Cmd Msg )
init flags =
    case GeneratedPreferences.decodeConfigurationFlags flags of
        Ok (Just settings) ->
            ( initialModel (Just settings), sendCompanionDefaults settings )

        Ok Nothing ->
            ( initialModel (Just CompanionPreferences.preferencesDefaults)
            , sendCompanionDefaults CompanionPreferences.preferencesDefaults
            )

        Err error ->
            ( initialModel (Just CompanionPreferences.preferencesDefaults)
                |> addError ("Initial configuration error: " ++ error)
            , sendCompanionDefaults CompanionPreferences.preferencesDefaults
            )


initialModel : Maybe CompanionPreferences.Settings -> Model
initialModel settings =
    { settings = settings
    , lastLocation = Nothing
    , errors = []
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestUpdate) ->
            ( model, sendSnapshot (currentSettings model) )

        FromWatch (Ok RequestSunData) ->
            ( model, sendSunData )

        FromWatch (Ok RequestWeather) ->
            ( model, sendWeatherData )

        FromWatch (Err error) ->
            ( addError ("Watch message error: " ++ error) model, Cmd.none )

        FromConfiguration (Ok settings) ->
            ( { model | settings = Just settings }, sendSnapshot settings )

        FromConfiguration (Err error) ->
            ( addError ("Configuration error: " ++ error) model, Cmd.none )

        CurrentPosition (Ok location) ->
            ( { model | lastLocation = Just location }
            , Task.perform (CurrentTime location) Time.now
            )

        CurrentPosition (Err error) ->
            ( addError ("Location error: " ++ error) model, Cmd.none )

        CurrentTime location now ->
            ( model, sendLocationSnapshot location now )

        GotWeather (Ok (Weather.Current info)) ->
            ( model, sendWeatherSnapshot info )

        GotWeather (Ok _) ->
            ( model, Cmd.none )

        GotWeather (Err error) ->
            ( addError ("Weather error: " ++ error) model, Cmd.none )

        GotEnvironment (Ok info) ->
            ( model
            , Cmd.batch
                [ sendEnvironmentSnapshot info
                , sendTideSnapshot info.tide
                ]
            )

        GotEnvironment (Err error) ->
            ( addError ("Environment error: " ++ error) model, Cmd.none )


currentSettings : Model -> CompanionPreferences.Settings
currentSettings model =
    Maybe.withDefault CompanionPreferences.preferencesDefaults model.settings


sendSnapshot : CompanionPreferences.Settings -> Cmd Msg
sendSnapshot settings =
    Cmd.batch
        [ sendCompanionDefaults settings
        , sendSunData
        , sendWeatherData
        ]


sendSunData : Cmd Msg
sendSunData =
    requestCurrentLocation


sendWeatherData : Cmd Msg
sendWeatherData =
    refreshWeather


sendCompanionDefaults : CompanionPreferences.Settings -> Cmd Msg
sendCompanionDefaults settings =
    CompanionPhone.sendPhoneToWatch
        (SetCornerUpdateInterval (CompanionPreferences.intervalSeconds settings.cornerUpdateInterval))


requestCurrentLocation : Cmd Msg
requestCurrentLocation =
    Geolocation.currentPosition CurrentPosition


refreshWeather : Cmd Msg
refreshWeather =
    Weather.current (GotWeather << Result.map Weather.Current)


sendEnvironmentSnapshot : Environment.EnvironmentInfo -> Cmd Msg
sendEnvironmentSnapshot info =
    Cmd.batch <|
        List.filterMap identity
            [ Maybe.map sendSunSnapshot info.sun
            , Maybe.map sendMoonSnapshot info.moon
            ]


sendSunSnapshot : Environment.SunInfo -> Cmd Msg
sendSunSnapshot sun =
    CompanionPhone.sendPhoneToWatch
        (ProvideSun sun.sunriseMin sun.sunsetMin (sunModeFromInfo sun))


sendMoonSnapshot : Environment.MoonInfo -> Cmd Msg
sendMoonSnapshot moon =
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch
            (ProvideMoon
                (Maybe.withDefault 0 moon.moonriseMin)
                (Maybe.withDefault 0 moon.moonsetMin)
                moon.phaseE6
            )
        , CompanionPhone.sendPhoneToWatch (ProvideMoonPhase moon.phaseE6)
        ]


sunModeFromInfo : Environment.SunInfo -> SunMode
sunModeFromInfo sun =
    if sun.polarDay then
        PolarDay

    else
        SunCycle


refreshEnvironment : Cmd Msg
refreshEnvironment =
    Cmd.batch
        [ Environment.setup
        , Environment.current GotEnvironment
        ]


sendLocationSnapshot : LocationSnapshot -> Time.Posix -> Cmd Msg
sendLocationSnapshot location now =
    let
        tzOffsetMin =
            longitudeTimezoneOffset location.longitude

        sun =
            sunSnapshot location tzOffsetMin now

        moon =
            moonSnapshot location tzOffsetMin now
    in
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch (ProvideTimezone tzOffsetMin)
        , CompanionPhone.sendPhoneToWatch (ProvideSun sun.sunriseMin sun.sunsetMin sun.mode)
        , CompanionPhone.sendPhoneToWatch
            (ProvideMoon
                (Maybe.withDefault 0 moon.moonriseMin)
                (Maybe.withDefault 0 moon.moonsetMin)
                moon.phaseE6
            )
        , CompanionPhone.sendPhoneToWatch (ProvideMoonPhase moon.phaseE6)
        ]


sendWeatherSnapshot : Weather.WeatherInfo -> Cmd Msg
sendWeatherSnapshot info =
    let
        condition =
            toProtocolCondition info.condition

        pressure =
            Maybe.withDefault 0 info.pressureHpa

        windSpeed =
            Maybe.map kphToMetersPerSecond info.windKph

        windDirection =
            Maybe.map windDirectionFromDegrees info.windDirectionDeg
                |> Maybe.withDefault North
    in
    Cmd.batch
        ([ CompanionPhone.sendPhoneToWatch
            (ProvideWeather
                (Celsius (info.temperatureC * 10))
                condition
                0
                0
                pressure
            )
         ]
            ++ (case windSpeed of
                    Just speed ->
                        [ CompanionPhone.sendPhoneToWatch (ProvideWind windDirection (MetersPerSecond speed)) ]

                    Nothing ->
                        []
               )
        )


windDirectionFromDegrees : Int -> WindDirection
windDirectionFromDegrees degrees =
    let
        sector =
            modBy 8 (Basics.round (toFloat (modBy 360 degrees) / 45))
    in
    case sector of
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


sendTideSnapshot : Maybe Environment.TideInfo -> Cmd Msg
sendTideSnapshot maybeTide =
    case maybeTide of
        Just tide ->
            CompanionPhone.sendPhoneToWatch
                (ProvideTide
                    tide.nextMin
                    tide.levelCm
                    (tideProgress tide.nextMin)
                    (if tide.rising then
                        HighTide

                     else
                        LowTide
                    )
                )

        Nothing ->
            CompanionPhone.sendPhoneToWatch ClearTide


type alias SunSnapshot =
    { sunriseMin : Int
    , sunsetMin : Int
    , mode : SunMode
    }


type alias MoonSnapshot =
    { moonriseMin : Maybe Int
    , moonsetMin : Maybe Int
    , phaseE6 : Int
    }


type SolarEvent
    = SolarHours Float
    | SolarPolarDay
    | SolarPolarNight


sunSnapshot : LocationSnapshot -> Int -> Time.Posix -> SunSnapshot
sunSnapshot location tzOffsetMin now =
    let
        date =
            locationLocalDate tzOffsetMin now

        dayNumber =
            dayOfYear date.year date.month date.day

        sunrise =
            calcSolarEventLocalHours dayNumber location.latitude location.longitude tzOffsetMin True

        sunset =
            calcSolarEventLocalHours dayNumber location.latitude location.longitude tzOffsetMin False
    in
    case ( sunrise, sunset ) of
        ( SolarPolarDay, _ ) ->
            { sunriseMin = 0, sunsetMin = 0, mode = PolarDay }

        ( _, SolarPolarDay ) ->
            { sunriseMin = 0, sunsetMin = 0, mode = PolarDay }

        ( SolarPolarNight, _ ) ->
            { sunriseMin = 0, sunsetMin = 0, mode = PolarNight }

        ( _, SolarPolarNight ) ->
            { sunriseMin = 0, sunsetMin = 0, mode = PolarNight }

        ( SolarHours sunriseHour, SolarHours sunsetHour ) ->
            { sunriseMin = localHourToMinute sunriseHour
            , sunsetMin = localHourToMinute sunsetHour
            , mode = SunCycle
            }


calcSolarEventLocalHours : Int -> Float -> Float -> Int -> Bool -> SolarEvent
calcSolarEventLocalHours dayNumber latDeg lonDeg tzOffsetMin isSunrise =
    let
        lngHour =
            lonDeg / 15

        eventHour =
            if isSunrise then
                6

            else
                18

        t =
            toFloat dayNumber + ((toFloat eventHour - lngHour) / 24)

        meanAnomaly =
            (0.9856 * t) - 3.289

        trueLongitude =
            normalizeDegrees (meanAnomaly + (1.916 * sin (degrees meanAnomaly)) + (0.020 * sin (degrees (2 * meanAnomaly))) + 282.634)

        rightAscensionDegrees =
            normalizeDegrees (atan (0.91764 * tan (degrees trueLongitude)) * 180 / pi)

        trueLongitudeQuadrant =
            toFloat (floor (trueLongitude / 90)) * 90

        rightAscensionQuadrant =
            toFloat (floor (rightAscensionDegrees / 90)) * 90

        rightAscensionHours =
            (rightAscensionDegrees + (trueLongitudeQuadrant - rightAscensionQuadrant)) / 15

        sinDec =
            0.39782 * sin (degrees trueLongitude)

        cosDec =
            cos (asin sinDec)

        cosHour =
            (cos (degrees 90.833) - (sinDec * sin (degrees latDeg))) / (cosDec * cos (degrees latDeg))
    in
    if cosHour > 1 then
        SolarPolarNight

    else if cosHour < -1 then
        SolarPolarDay

    else
        let
            hourAngleDegrees =
                if isSunrise then
                    360 - (acos cosHour * 180 / pi)

                else
                    acos cosHour * 180 / pi

            localMeanTime =
                (hourAngleDegrees / 15) + rightAscensionHours - (0.06571 * t) - 6.622

            universalTime =
                normalizeHours (localMeanTime - lngHour)

            tzHours =
                toFloat tzOffsetMin / 60
        in
        SolarHours (normalizeHours (universalTime + tzHours))


moonSnapshot : LocationSnapshot -> Int -> Time.Posix -> MoonSnapshot
moonSnapshot location tzOffsetMin now =
    let
        events =
            moonEvents location tzOffsetMin now
    in
    { moonriseMin = events.rise
    , moonsetMin = events.set
    , phaseE6 = moonPhaseE6 now
    }


type alias MoonEvents =
    { rise : Maybe Int
    , set : Maybe Int
    }


type alias MoonScan =
    { rise : Maybe Int
    , set : Maybe Int
    , prevAbove : Maybe Bool
    , aboveSamples : Int
    , totalSamples : Int
    }


moonEvents : LocationSnapshot -> Int -> Time.Posix -> MoonEvents
moonEvents location tzOffsetMin now =
    let
        stepMin =
            10

        scan =
            scanMoonEvents location (localMidnightUtcMillis tzOffsetMin now) stepMin 0
                { rise = Nothing
                , set = Nothing
                , prevAbove = Nothing
                , aboveSamples = 0
                , totalSamples = 0
                }
    in
    { rise = scan.rise, set = scan.set }


scanMoonEvents : LocationSnapshot -> Int -> Int -> Int -> MoonScan -> MoonScan
scanMoonEvents location baseUtcMillis stepMin minute scan =
    if minute > 1440 then
        scan

    else
        let
            sampleMinute =
                if minute == 1440 then
                    1439

                else
                    minute

            above =
                moonAltitudeRad (Time.millisToPosix (baseUtcMillis + (sampleMinute * 60000))) location > degrees -0.3

            nextScan =
                case scan.prevAbove of
                    Nothing ->
                        { scan
                            | prevAbove = Just above
                            , aboveSamples = countAbove above scan.aboveSamples
                            , totalSamples = scan.totalSamples + 1
                        }

                    Just previousAbove ->
                        let
                            crossed =
                                above /= previousAbove

                            transitionMinute =
                                if crossed then
                                    refineMoonTransition location baseUtcMillis previousAbove (minute - stepMin) minute 10

                                else
                                    minute

                            rise =
                                if crossed && not previousAbove && above && scan.rise == Nothing then
                                    Just transitionMinute

                                else
                                    scan.rise

                            set =
                                if crossed && previousAbove && not above && scan.set == Nothing then
                                    Just transitionMinute

                                else
                                    scan.set
                        in
                        { scan
                            | rise = rise
                            , set = set
                            , prevAbove = Just above
                            , aboveSamples = countAbove above scan.aboveSamples
                            , totalSamples = scan.totalSamples + 1
                        }
        in
        scanMoonEvents location baseUtcMillis stepMin (minute + stepMin) nextScan


refineMoonTransition : LocationSnapshot -> Int -> Bool -> Int -> Int -> Int -> Int
refineMoonTransition location baseUtcMillis previousAbove low high remaining =
    if remaining <= 0 || high - low <= 1 then
        clamp 0 1439 high

    else
        let
            mid =
                (low + high) // 2

            above =
                moonAltitudeRad (Time.millisToPosix (baseUtcMillis + (mid * 60000))) location > degrees -0.3
        in
        if above == previousAbove then
            refineMoonTransition location baseUtcMillis previousAbove mid high (remaining - 1)

        else
            refineMoonTransition location baseUtcMillis previousAbove low mid (remaining - 1)


countAbove : Bool -> Int -> Int
countAbove above count =
    if above then
        count + 1

    else
        count


type alias MoonCoordinates =
    { ra : Float
    , dec : Float
    }


moonAltitudeRad : Time.Posix -> LocationSnapshot -> Float
moonAltitudeRad time location =
    let
        moon =
            moonCoordinates time

        lat =
            degrees location.latitude

        lst =
            degrees ((gmstHours time * 15) + location.longitude)

        hourAngle =
            normalizeRadians (lst - moon.ra)
    in
    asin ((sin lat * sin moon.dec) + (cos lat * cos moon.dec * cos hourAngle))


moonCoordinates : Time.Posix -> MoonCoordinates
moonCoordinates time =
    let
        d =
            julianDay time - 2451543.5

        node =
            normalizeDegrees (125.1228 - (0.0529538083 * d))

        inclination =
            5.1454

        argPerigee =
            normalizeDegrees (318.0634 + (0.1643573223 * d))

        meanAnomaly =
            normalizeDegrees (115.3654 + (13.0649929509 * d))

        eccentricity =
            0.0549

        eccentricAnomaly =
            meanAnomaly + (eccentricity * (180 / pi) * sin (degrees meanAnomaly) * (1 + (eccentricity * cos (degrees meanAnomaly))))

        xv =
            60.2666 * (cos (degrees eccentricAnomaly) - eccentricity)

        yv =
            60.2666 * (sqrt (1 - (eccentricity * eccentricity)) * sin (degrees eccentricAnomaly))

        trueAnomaly =
            atan2 yv xv

        distance =
            sqrt ((xv * xv) + (yv * yv))

        lon =
            trueAnomaly + degrees argPerigee

        nodeRad =
            degrees node

        incRad =
            degrees inclination

        xh =
            distance * ((cos nodeRad * cos lon) - (sin nodeRad * sin lon * cos incRad))

        yh =
            distance * ((sin nodeRad * cos lon) + (cos nodeRad * sin lon * cos incRad))

        zh =
            distance * (sin lon * sin incRad)

        obliquity =
            degrees (23.4393 - (0.0000003563 * d))

        xe =
            xh

        ye =
            (yh * cos obliquity) - (zh * sin obliquity)

        ze =
            (yh * sin obliquity) + (zh * cos obliquity)

        ra =
            normalizeRadians (atan2 ye xe)

        dec =
            atan2 ze (sqrt ((xe * xe) + (ye * ye)))
    in
    { ra = ra, dec = dec }


moonPhaseE6 : Time.Posix -> Int
moonPhaseE6 now =
    let
        knownNewMoonMillis =
            947182440000

        synodicMonthMillis =
            2551442877.0

        lunations =
            toFloat (Time.posixToMillis now - knownNewMoonMillis) / synodicMonthMillis
    in
    clamp 0 1000000 (round (fractionalPart lunations * 1000000))


locationLocalDate : Int -> Time.Posix -> { year : Int, month : Int, day : Int }
locationLocalDate tzOffsetMin now =
    let
        shifted =
            Time.millisToPosix (Time.posixToMillis now + (tzOffsetMin * 60000))
    in
    { year = Time.toYear Time.utc shifted
    , month = monthNumber (Time.toMonth Time.utc shifted)
    , day = Time.toDay Time.utc shifted
    }


localMidnightUtcMillis : Int -> Time.Posix -> Int
localMidnightUtcMillis tzOffsetMin now =
    let
        localMillis =
            Time.posixToMillis now + (tzOffsetMin * 60000)

        localDayStart =
            (localMillis // 86400000) * 86400000
    in
    localDayStart - (tzOffsetMin * 60000)


longitudeTimezoneOffset : Float -> Int
longitudeTimezoneOffset longitude =
    round (longitude / 15) * 60


julianDay : Time.Posix -> Float
julianDay time =
    2440587.5 + (toFloat (Time.posixToMillis time) / 86400000)


gmstHours : Time.Posix -> Float
gmstHours time =
    normalizeHours (18.697374558 + (24.06570982441908 * (julianDay time - 2451545.0)))


localHourToMinute : Float -> Int
localHourToMinute hour =
    modBy 1440 (round (hour * 60))


dayOfYear : Int -> Int -> Int -> Int
dayOfYear year month day =
    let
        monthLengths =
            [ 31, februaryLength year, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ]
    in
    List.take (month - 1) monthLengths
        |> List.sum
        |> (+) day


februaryLength : Int -> Int
februaryLength year =
    if isLeapYear year then
        29

    else
        28


isLeapYear : Int -> Bool
isLeapYear year =
    (modBy 4 year == 0 && modBy 100 year /= 0) || modBy 400 year == 0


monthNumber : Time.Month -> Int
monthNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12


normalizeDegrees : Float -> Float
normalizeDegrees value =
    let
        normalized =
            value - (toFloat (floor (value / 360)) * 360)
    in
    if normalized < 0 then
        normalized + 360

    else
        normalized


normalizeHours : Float -> Float
normalizeHours value =
    let
        normalized =
            value - (toFloat (floor (value / 24)) * 24)
    in
    if normalized < 0 then
        normalized + 24

    else
        normalized


normalizeRadians : Float -> Float
normalizeRadians radians =
    let
        turn =
            2 * pi

        normalized =
            radians - (toFloat (floor (radians / turn)) * turn)
    in
    if normalized > pi then
        normalized - turn

    else if normalized < -pi then
        normalized + turn

    else
        normalized


fractionalPart : Float -> Float
fractionalPart value =
    let
        fraction =
            value - toFloat (floor value)
    in
    if fraction < 0 then
        fraction + 1

    else
        fraction


kphToMetersPerSecond : Int -> Int
kphToMetersPerSecond kph =
    round (toFloat kph / 3.6)


tideProgress : Int -> Int
tideProgress minutesUntilNext =
    clamp 0 1000 (1000 - ((clamp 0 360 minutesUntilNext * 1000) // 360))


toProtocolCondition : Weather.Condition -> WeatherCondition
toProtocolCondition condition =
    case condition of
        Weather.Clear ->
            Clear

        Weather.Cloudy ->
            Cloudy

        Weather.Fog ->
            Fog

        Weather.Drizzle ->
            Drizzle

        Weather.Rain ->
            Rain

        Weather.Snow ->
            Snow

        Weather.Showers ->
            Showers

        Weather.Storm ->
            Storm

        Weather.UnknownWeather ->
            UnknownWeather


addError : String -> Model -> Model
addError error model =
    { model | errors = model.errors ++ [ error ] }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , GeneratedPreferences.onConfiguration FromConfiguration
        , Geolocation.onCurrentPosition CurrentPosition
        , Weather.onWeather GotWeather
        , Environment.onEnvironment GotEnvironment
        ]


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
