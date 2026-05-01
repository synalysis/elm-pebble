module CompanionApp exposing (main)

import Companion.Phone as CompanionPhone
import Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), WatchToPhone(..), WeatherCondition(..))
import CompanionPreferences
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.AppMessage as RawBridge
import Pebble.Companion.Preferences as Preferences
import Platform


type alias Model =
    { lastResponse : Int
    }


type alias WeatherReport =
    { temperature : Float
    , condition : WeatherCondition
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | FromBridge Decode.Value
    | WeatherReceived (Result Http.Error WeatherReport)
    | DemoPosted (Result Http.Error String)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { lastResponse = 0 }, Cmd.none )


locationQuery : Location -> String
locationQuery location =
    case location of
        CurrentLocation ->
            "latitude=52.52&longitude=13.41" -- Demo fallback location

        Berlin ->
            "latitude=52.52&longitude=13.41" -- Berlin

        Zurich ->
            "latitude=47.37&longitude=8.54" -- Zurich

        NewYork ->
            "latitude=40.71&longitude=-74.01" -- New York


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok (RequestWeather location)) ->
            let
                weatherRequest =
                    Http.get
                        { url = "https://api.open-meteo.com/v1/forecast?" ++ locationQuery location ++ "&current=temperature_2m,weather_code&forecast_days=1"
                        , expect =
                            Http.expectJson
                                WeatherReceived
                                weatherReportDecoder
                        }

                demoPostRequest =
                    Http.post
                        { url = "https://postman-echo.com/post"
                        , body =
                            Http.jsonBody
                                (Encode.object
                                    [ ( "event", Encode.string "weather-request" )
                                    , ( "location", Encode.string (locationName location) )
                                    ]
                                )
                        , expect =
                            Http.expectString
                                (\result ->
                                    case result of
                                        Ok body ->
                                            DemoPosted (Ok body)

                                        Err err ->
                                            DemoPosted (Err err)
                                )
                        }
            in
            ( model
            , Cmd.batch
                [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius 0))
                , CompanionPhone.sendPhoneToWatch (ProvideCondition Clear)
                , weatherRequest
                , demoPostRequest
                ]
            )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        FromBridge value ->
            case decodeConfigurationSaved value of
                Ok settings ->
                    ( model, sendSettings settings )

                Err _ ->
                    ( model, Cmd.none )

        WeatherReceived result ->
            case result of
                Ok weather ->
                    let
                        rounded =
                            round weather.temperature
                    in
                    ( { model | lastResponse = rounded }
                    , Cmd.batch
                        [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius rounded))
                        , CompanionPhone.sendPhoneToWatch (ProvideCondition weather.condition)
                        ]
                    )

                Err _ ->
                    ( { model | lastResponse = 0 }
                    , Cmd.batch
                        [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius 0))
                        , CompanionPhone.sendPhoneToWatch (ProvideCondition Clear)
                        ]
                    )

        DemoPosted _ ->
            ( model, Cmd.none )


decodeConfigurationSaved : Decode.Value -> Result String CompanionPreferences.Settings
decodeConfigurationSaved value =
    Decode.decodeValue configurationResponseDecoder value
        |> Result.mapError Decode.errorToString
        |> Result.andThen
            (\response ->
                Preferences.decodeResponse CompanionPreferences.settings response
                    |> Result.mapError preferencesErrorToString
            )


configurationResponseDecoder : Decode.Decoder (Maybe String)
configurationResponseDecoder =
    Decode.field "event" Decode.string
        |> Decode.andThen
            (\event ->
                if event == "configuration.closed" then
                    Decode.at [ "payload", "response" ] (Decode.nullable Decode.string)

                else
                    Decode.fail ("Unexpected bridge event: " ++ event)
            )


preferencesErrorToString : Preferences.Error -> String
preferencesErrorToString error =
    case error of
        Preferences.InvalidJson message ->
            message

        Preferences.MissingResponse ->
            "Configuration closed without a response"


sendSettings : CompanionPreferences.Settings -> Cmd Msg
sendSettings settings =
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch (SetBackgroundColor settings.backgroundColor)
        , CompanionPhone.sendPhoneToWatch (SetTextColor settings.textColor)
        , CompanionPhone.sendPhoneToWatch (SetShowDate settings.showDate)
        ]


locationName : Location -> String
locationName location =
    case location of
        CurrentLocation ->
            "CurrentLocation"

        Berlin ->
            "Berlin"

        Zurich ->
            "Zurich"

        NewYork ->
            "NewYork"


weatherReportDecoder : Decode.Decoder WeatherReport
weatherReportDecoder =
    Decode.field "current"
        (Decode.map2 WeatherReport
            (Decode.field "temperature_2m" Decode.float)
            (Decode.field "weather_code" (Decode.map conditionFromCode Decode.int))
        )


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


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , RawBridge.onMessage FromBridge
        ]


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
