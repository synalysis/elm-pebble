module CompanionApp exposing (main)

import Companion.Phone as CompanionPhone
import Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), WatchToPhone(..), WeatherCondition(..))
import Http
import Json.Decode as Decode
import Json.Encode as Encode
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
                [ weatherRequest
                , demoPostRequest
                ]
            )

        FromWatch (Err _) ->
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
                    ( model, Cmd.none )

        DemoPosted _ ->
            ( model, Cmd.none )


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
    CompanionPhone.onWatchToPhone FromWatch


main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
