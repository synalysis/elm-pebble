module CompanionApp exposing (main)

import Companion.GeneratedPreferences as GeneratedPreferences
import Companion.Phone as CompanionPhone
import Companion.Types exposing (AltitudeUnit(..), InternetMode(..), PhoneToWatch(..), SunMode(..), TemperatureUnit(..), TideKind(..), WatchToPhone(..), WeatherCondition(..), WindUnit(..))
import CompanionPreferences
import Http
import Json.Decode as Decode
import Platform


type alias Model =
    { settings : Maybe CompanionPreferences.Settings
    , errors : List String
    }


type alias Flags =
    Decode.Value


type alias WeatherReport =
    { tempC10 : Int
    , condition : WeatherCondition
    , windDir : Int
    , windSpeedMs : Int
    , precipMm10 : Int
    , uv10 : Int
    , pressureHpa : Int
    , altitudeM : Int
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | FromBridge (Result String CompanionPreferences.Settings)
    | WeatherReceived (Result Http.Error WeatherReport)


init : Flags -> ( Model, Cmd Msg )
init flags =
    case GeneratedPreferences.decodeConfigurationFlags flags of
        Ok (Just settings) ->
            ( { settings = Just settings, errors = [] }, sendSnapshot settings )

        Ok Nothing ->
            ( { settings = Just CompanionPreferences.preferencesDefaults, errors = [] }
            , sendSnapshot CompanionPreferences.preferencesDefaults
            )

        Err error ->
            ( { settings = Just CompanionPreferences.preferencesDefaults, errors = [ "Initial configuration error: " ++ error ] }
            , sendSnapshot CompanionPreferences.preferencesDefaults
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestUpdate) ->
            ( model, sendSnapshot (currentSettings model) )

        FromWatch (Err error) ->
            ( addError ("Watch message error: " ++ error) model, Cmd.none )

        FromBridge (Ok settings) ->
            ( { model | settings = Just settings }, sendSnapshot settings )

        FromBridge (Err error) ->
            ( addError ("Configuration error: " ++ error) model, Cmd.none )

        WeatherReceived result ->
            let
                settings =
                    currentSettings model
            in
            case result of
                Ok report ->
                    ( model, sendReport settings report )

                Err error ->
                    ( addError ("Weather request error: " ++ httpErrorToString error) model
                    , sendReport settings (fallbackReport settings)
                    )


currentSettings : Model -> CompanionPreferences.Settings
currentSettings model =
    Maybe.withDefault CompanionPreferences.preferencesDefaults model.settings


sendSnapshot : CompanionPreferences.Settings -> Cmd Msg
sendSnapshot settings =
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch (ProvideLocation (round (settings.homeLatitude * 1000000)) (round (settings.homeLongitude * 1000000)) (round settings.homeTzOffsetMinutes))
        , CompanionPhone.sendPhoneToWatch (SetUseInternet settings.internetMode)
        , CompanionPhone.sendPhoneToWatch (SetUnits settings.temperatureUnit settings.windUnit)
        , CompanionPhone.sendPhoneToWatch (ProvideSun 360 1080 SunCycle)
        , CompanionPhone.sendPhoneToWatch (ProvideMoon 118 780 (moonPhaseFor settings))
        , CompanionPhone.sendPhoneToWatch (ProvideMoonPhase (moonPhaseFor settings))
        , if settings.showTide then
            CompanionPhone.sendPhoneToWatch (ProvideTide 372 90 420 HighTide)

          else
            CompanionPhone.sendPhoneToWatch ClearTide
        , if settings.internetMode == InternetEnabled then
            fetchWeather settings

          else
            sendReport settings (fallbackReport settings)
        ]


fetchWeather : CompanionPreferences.Settings -> Cmd Msg
fetchWeather settings =
    Http.get
        { url = weatherUrl settings
        , expect = Http.expectJson WeatherReceived weatherDecoder
        }


sendReport : CompanionPreferences.Settings -> WeatherReport -> Cmd Msg
sendReport settings report =
    let
        windSpeed =
            if settings.windUnit == MilesPerHour then
                round (toFloat report.windSpeedMs * 2.237)

            else
                report.windSpeedMs
    in
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch
            (ProvideWeather
                report.tempC10
                report.condition
                report.precipMm10
                report.uv10
                report.pressureHpa
                settings.temperatureUnit
            )
        , CompanionPhone.sendPhoneToWatch (ProvideWind report.windDir windSpeed settings.windUnit)
        , CompanionPhone.sendPhoneToWatch (ProvideAltitude report.altitudeM (altitudeUnit settings.windUnit))
        ]


altitudeUnit : WindUnit -> AltitudeUnit
altitudeUnit unit =
    if unit == MilesPerHour then
        Feet

    else
        Meters


weatherUrl : CompanionPreferences.Settings -> String
weatherUrl settings =
    "https://api.open-meteo.com/v1/forecast?latitude="
        ++ String.fromFloat settings.homeLatitude
        ++ "&longitude="
        ++ String.fromFloat settings.homeLongitude
        ++ "&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation,uv_index,surface_pressure&forecast_days=1"


weatherDecoder : Decode.Decoder WeatherReport
weatherDecoder =
    Decode.map8 WeatherReport
        (Decode.at [ "current", "temperature_2m" ] (Decode.map (\v -> round (v * 10)) Decode.float))
        (Decode.at [ "current", "weather_code" ] (Decode.map conditionFromCode Decode.int))
        (Decode.at [ "current", "wind_direction_10m" ] (Decode.map windSector Decode.float))
        (Decode.at [ "current", "wind_speed_10m" ] (Decode.map round Decode.float))
        (Decode.at [ "current", "precipitation" ] (Decode.map (\v -> round (v * 10)) Decode.float))
        (Decode.at [ "current", "uv_index" ] (Decode.map (\v -> round (v * 10)) Decode.float))
        (Decode.at [ "current", "surface_pressure" ] (Decode.map round Decode.float))
        (Decode.field "elevation" (Decode.map round Decode.float))


fallbackReport : CompanionPreferences.Settings -> WeatherReport
fallbackReport settings =
    { tempC10 = 180
    , condition = Clear
    , windDir = windSector (settings.homeLongitude * 10)
    , windSpeedMs = 4
    , precipMm10 = 0
    , uv10 = 20
    , pressureHpa = 1013
    , altitudeM = 34
    }


moonPhaseFor : CompanionPreferences.Settings -> Int
moonPhaseFor settings =
    modBy 1000000 (round (abs settings.homeLatitude * 10000 + abs settings.homeLongitude * 20000))


windSector : Float -> Int
windSector degrees =
    modBy 8 (round ((degrees + 22.5) / 45))


conditionFromCode : Int -> WeatherCondition
conditionFromCode code =
    if code == 0 then
        Clear

    else if code <= 3 then
        Cloudy

    else if code <= 48 then
        Fog

    else if code <= 57 then
        Drizzle

    else if code <= 67 then
        Rain

    else if code <= 77 then
        Snow

    else if code <= 86 then
        Showers

    else if code <= 99 then
        Storm

    else
        UnknownWeather


addError : String -> Model -> Model
addError error model =
    { model | errors = model.errors ++ [ error ] }


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Timed out"

        Http.NetworkError ->
            "Network error"

        Http.BadStatus status ->
            "Bad status: " ++ String.fromInt status

        Http.BadBody message ->
            "Bad body: " ++ message


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , GeneratedPreferences.onConfiguration FromBridge
        ]


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
