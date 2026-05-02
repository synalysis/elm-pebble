module CompanionApp exposing (main)

import Companion.Phone as CompanionPhone
import Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), WatchToPhone(..), WeatherCondition(..))
import CompanionPreferences
import Companion.GeneratedPreferences as GeneratedPreferences
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Platform


type alias Model =
    { lastResponse : Int
    , errors : List String
    }


type alias Flags =
    Decode.Value


type alias WeatherReport =
    { temperature : Float
    , condition : WeatherCondition
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | FromBridge (Result String CompanionPreferences.Settings)
    | WeatherReceived (Result Http.Error WeatherReport)
    | DemoPosted (Result Http.Error String)


init : Flags -> ( Model, Cmd Msg )
init flags =
    case GeneratedPreferences.decodeConfigurationFlags flags of
        Ok (Just settings) ->
            ( initialModel, sendSettings settings )

        Ok Nothing ->
            ( initialModel, Cmd.none )

        Err error ->
            ( addError ("Initial configuration error: " ++ error) initialModel, Cmd.none )


initialModel : Model
initialModel =
    { lastResponse = 0, errors = [] }


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

        FromWatch (Err error) ->
            ( addError ("Watch message error: " ++ error) model, Cmd.none )

        FromBridge (Ok settings) ->
            ( model, sendSettings settings )

        FromBridge (Err error) ->
            ( addError ("Configuration error: " ++ error) model, Cmd.none )

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

                Err error ->
                    ( { model | lastResponse = 0 }
                        |> addError ("Weather request error: " ++ httpErrorToString error)
                    , Cmd.batch
                        [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius 0))
                        , CompanionPhone.sendPhoneToWatch (ProvideCondition Clear)
                        ]
                    )

        DemoPosted (Ok _) ->
            ( model, Cmd.none )

        DemoPosted (Err error) ->
            ( addError ("Demo POST error: " ++ httpErrorToString error) model, Cmd.none )


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
        , GeneratedPreferences.onConfiguration FromBridge
        ]


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
