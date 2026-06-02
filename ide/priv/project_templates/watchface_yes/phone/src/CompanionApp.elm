module CompanionApp exposing (main)

import Companion.GeneratedPreferences as GeneratedPreferences
import Pebble.Companion.Geolocation as Geolocation
import Pebble.Companion.Phone as CompanionPhone
import Companion.Types exposing (PhoneToWatch(..), SunMode(..), WatchToPhone(..))
import CompanionPreferences
import Json.Decode as Decode
import Platform
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


init : Flags -> ( Model, Cmd Msg )
init flags =
    case GeneratedPreferences.decodeConfigurationFlags flags of
        Ok (Just settings) ->
            ( { settings = Just settings, lastLocation = Nothing, errors = [] }, sendSnapshot settings )

        Ok Nothing ->
            ( { settings = Just CompanionPreferences.preferencesDefaults, lastLocation = Nothing, errors = [] }
            , sendSnapshot CompanionPreferences.preferencesDefaults
            )

        Err error ->
            ( { settings = Just CompanionPreferences.preferencesDefaults, lastLocation = Nothing, errors = [ "Initial configuration error: " ++ error ] }
            , sendSnapshot CompanionPreferences.preferencesDefaults
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestUpdate) ->
            ( model, sendSnapshot (currentSettings model) )

        FromWatch (Err error) ->
            ( addError ("Watch message error: " ++ error) model, Cmd.none )

        FromConfiguration (Ok settings) ->
            ( { model | settings = Just settings }, sendSnapshot settings )

        FromConfiguration (Err error) ->
            ( addError ("Configuration error: " ++ error) model, Cmd.none )

        CurrentPosition (Ok location) ->
            ( { model | lastLocation = Just location }
            , sendLocationData location
            )

        CurrentPosition (Err error) ->
            ( addError ("Location error: " ++ error) model, Cmd.none )


currentSettings : Model -> CompanionPreferences.Settings
currentSettings model =
    Maybe.withDefault CompanionPreferences.preferencesDefaults model.settings


sendSnapshot : CompanionPreferences.Settings -> Cmd Msg
sendSnapshot _ =
    requestCurrentLocation


requestCurrentLocation : Cmd Msg
requestCurrentLocation =
    Geolocation.currentPosition CurrentPosition


sendLocationData : LocationSnapshot -> Cmd Msg
sendLocationData location =
    sendLocationSnapshot location


sendLocationSnapshot : LocationSnapshot -> Cmd Msg
sendLocationSnapshot location =
    let
        -- Avoid Time.getZoneName in phone JS: Intl.DateTimeFormat exhausts V8 memory in pypkjs.
        tzOffsetMin =
            longitudeTimezoneOffset location.longitude

        sunriseMin =
            sunriseMinute location tzOffsetMin

        sunsetMin =
            sunsetMinute location tzOffsetMin

        moonPhase =
            moonPhaseForLocation location
    in
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch (ProvideLocation (round (location.latitude * 1000000)) (round (location.longitude * 1000000)) tzOffsetMin)
        , CompanionPhone.sendPhoneToWatch (ProvideSun sunriseMin sunsetMin SunCycle)
        , CompanionPhone.sendPhoneToWatch (ProvideMoon 118 780 moonPhase)
        , CompanionPhone.sendPhoneToWatch (ProvideMoonPhase moonPhase)
        ]


moonPhaseForLocation : LocationSnapshot -> Int
moonPhaseForLocation location =
    modBy 1000000 (round (abs location.latitude * 10000 + abs location.longitude * 20000))


type SolarEvent
    = SolarHours Float
    | SolarPolarDay
    | SolarPolarNight


type alias SunSnapshot =
    { sunriseMin : Int
    , sunsetMin : Int
    , mode : SunMode
    }


longitudeTimezoneOffset : Float -> Int
longitudeTimezoneOffset longitude =
    round (longitude / 15) * 60


calcSunriseSunset : LocationSnapshot -> Int -> Time.Posix -> SunSnapshot
calcSunriseSunset location tzOffsetMin _ =
    { sunriseMin = sunriseMinute location tzOffsetMin
    , sunsetMin = sunsetMinute location tzOffsetMin
    , mode = SunCycle
    }


sunriseMinute : LocationSnapshot -> Int -> Int
sunriseMinute location tzOffsetMin =
    let
        solarNoon =
            720 + tzOffsetMin - round (location.longitude * 4)

        daylightMinutes =
            clamp 480 960 (900 - round (abs location.latitude * 3))

        halfDaylight =
            daylightMinutes // 2
    in
    modBy 1440 (solarNoon - halfDaylight)


sunsetMinute : LocationSnapshot -> Int -> Int
sunsetMinute location tzOffsetMin =
    let
        solarNoon =
            720 + tzOffsetMin - round (location.longitude * 4)

        daylightMinutes =
            clamp 480 960 (900 - round (abs location.latitude * 3))

        halfDaylight =
            daylightMinutes // 2
    in
    modBy 1440 (solarNoon + halfDaylight)


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


calcSolarEventLocalHours : Int -> Float -> Float -> Float -> Bool -> SolarEvent
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
            toFloat dayNumber + ((eventHour - lngHour) / 24)

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

            hourAngleHours =
                hourAngleDegrees / 15

            localMeanTime =
                hourAngleHours + rightAscensionHours - (0.06571 * t) - 6.622

            universalTime =
                normalizeHours (localMeanTime - lngHour)
        in
        SolarHours (normalizeHours (universalTime + (tzOffsetMin / 60)))


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


addError : String -> Model -> Model
addError error model =
    { model | errors = model.errors ++ [ error ] }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , GeneratedPreferences.onConfiguration FromConfiguration
        , Geolocation.onCurrentPosition CurrentPosition
        ]


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
