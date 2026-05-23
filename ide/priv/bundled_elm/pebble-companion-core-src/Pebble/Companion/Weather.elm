module Pebble.Companion.Weather exposing
    ( Condition(..)
    , WeatherInfo
    , WeatherUpdate(..)
    , current
    , forecast
    , onWeather
    , onCurrent
    , onForecast
    , setup
    , setupCurrent
    , setupForecast
    )

{-| Platform-provided weather for companion apps.

Weather comes from the Pebble companion bridge (IDE simulator settings or the
phone companion runtime). These functions do **not** take a city name or other
weather query.

    import Pebble.Companion.Weather as Weather

    type Msg
        = GotCurrent (Result String Weather.WeatherInfo)
        | GotForecast (Result String (List Weather.WeatherInfo))
        | GotWeatherPush (Result String Weather.WeatherUpdate)

    init _ =
        ( model, Weather.current GotCurrent )

    subscriptions _ =
        Weather.onWeather GotWeatherPush

    update msg model =
        case msg of
            GotCurrent (Ok info) ->
                ( { model | tempC = info.temperatureC }, Cmd.none )

            GotCurrent (Err error) ->
                ( { model | weatherError = Just error }, Cmd.none )

            GotForecast _ ->
                ( model, Cmd.none )

            GotWeatherPush (Ok (Weather.Current info)) ->
                ( { model | tempC = info.temperatureC }, Cmd.none )

            GotWeatherPush _ ->
                ( model, Cmd.none )

# Types

@docs Condition, WeatherInfo, WeatherUpdate

# Commands

@docs current, forecast

# Subscriptions

@docs onWeather, onCurrent, onForecast

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Platform-normalized weather condition.
-}
type Condition
    = Clear
    | Cloudy
    | Fog
    | Drizzle
    | Rain
    | Snow
    | Showers
    | Storm
    | UnknownWeather


{-| Current or forecast weather values.
-}
type alias WeatherInfo =
    { temperatureC : Int
    , condition : Condition
    , humidityPercent : Maybe Int
    , pressureHpa : Maybe Int
    , windKph : Maybe Int
    }


{-| A pushed weather update from the companion bridge.
-}
type WeatherUpdate
    = Current WeatherInfo
    | Forecast (List WeatherInfo)


{-| Request the current platform weather snapshot.
-}
current : (Result String WeatherInfo -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "weather-current" "weather" "current" decodeCurrentResponse


{-| Request forecast snapshots from the platform weather service.
-}
forecast : (Result String (List WeatherInfo) -> msg) -> Cmd msg
forecast toMsg =
    Phone.send toMsg <|
        Phone.request "weather-forecast" "weather" "forecast" decodeForecastResponse


{-| Receive pushed weather updates from the companion bridge.

Registering this subscription also tells the bridge to send weather updates.
-}
onWeather : (Result String WeatherUpdate -> msg) -> Sub msg
onWeather toMsg =
    Platform.subscribe (handler toMsg)


{-| Receive current-weather command responses on the dedicated weather port.
-}
onCurrent : (Result String WeatherInfo -> msg) -> Sub msg
onCurrent toMsg =
    Platform.subscribe (handlerCurrent toMsg)


{-| Receive forecast command responses on the dedicated weather port.
-}
onForecast : (Result String (List WeatherInfo) -> msg) -> Sub msg
onForecast toMsg =
    Platform.subscribe (handlerForecast toMsg)


setup : Cmd msg
setup =
    Platform.setup weatherPushInterest


setupCurrent : Cmd msg
setupCurrent =
    Platform.setup weatherCurrentInterest


setupForecast : Cmd msg
setupForecast =
    Platform.setup weatherForecastInterest


handler toMsg =
    Platform.handler weatherPushInterest decodeWeatherUpdate toMsg


handlerCurrent toMsg =
    Platform.handler weatherCurrentInterest decodeCurrentResponse toMsg


handlerForecast toMsg =
    Platform.handler weatherForecastInterest decodeForecastResponse toMsg


weatherPushInterest =
    Platform.interest
        { id = "weather"
        , subscribeCommand =
            Just <|
                Command.command "weather-subscribe" "weather" "subscribe"
        , eventPrefixes = [ "weather." ]
        , resultIdPrefixes = []
        }


weatherCurrentInterest =
    Platform.interest
        { id = "weather-current"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "weather-current" ]
        }


weatherForecastInterest =
    Platform.interest
        { id = "weather-forecast"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "weather-forecast" ]
        }


decodeCurrentResponse : Decode.Value -> Result String WeatherInfo
decodeCurrentResponse value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeCurrentBridgeEvent event

        Err _ ->
            decodeCurrentBridgeResult value


decodeForecastResponse : Decode.Value -> Result String (List WeatherInfo)
decodeForecastResponse value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeForecastBridgeEvent event

        Err _ ->
            decodeForecastBridgeResult value


decodeWeatherUpdate : Decode.Value -> Result String WeatherUpdate
decodeWeatherUpdate value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeWeatherUpdateEvent event

        Err _ ->
            decodeWeatherUpdateResult value


decodeCurrentBridgeEvent : BridgeEvent -> Result String WeatherInfo
decodeCurrentBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "weather.current" ->
            Decode.decodeValue decodeWeatherInfo bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "weather.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Weather unavailable")

        other ->
            Err ("Unexpected weather event: " ++ other)


decodeForecastBridgeEvent : BridgeEvent -> Result String (List WeatherInfo)
decodeForecastBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "weather.forecast" ->
            Decode.decodeValue (Decode.field "forecast" (Decode.list decodeWeatherInfo)) bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "weather.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Weather unavailable")

        other ->
            Err ("Unexpected weather event: " ++ other)


decodeWeatherUpdateEvent : BridgeEvent -> Result String WeatherUpdate
decodeWeatherUpdateEvent bridgeEvent =
    case bridgeEvent.event of
        "weather.current" ->
            Decode.decodeValue decodeWeatherInfo bridgeEvent.payload
                |> Result.map Current
                |> Result.mapError Decode.errorToString

        "weather.forecast" ->
            Decode.decodeValue (Decode.field "forecast" (Decode.list decodeWeatherInfo)) bridgeEvent.payload
                |> Result.map Forecast
                |> Result.mapError Decode.errorToString

        "weather.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Weather unavailable")

        other ->
            Err ("Unexpected weather event: " ++ other)


decodeCurrentBridgeResult : Decode.Value -> Result String WeatherInfo
decodeCurrentBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Weather response missing payload"

                    Just payload ->
                        decodeCurrentBridgeEvent { event = "weather.current", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeForecastBridgeResult : Decode.Value -> Result String (List WeatherInfo)
decodeForecastBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Weather response missing payload"

                    Just payload ->
                        decodeForecastBridgeEvent { event = "weather.forecast", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeWeatherUpdateResult : Decode.Value -> Result String WeatherUpdate
decodeWeatherUpdateResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Weather response missing payload"

                    Just payload ->
                        decodeWeatherUpdateEvent { event = "weather.current", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Weather unavailable"


decodeWeatherInfo : Decode.Decoder WeatherInfo
decodeWeatherInfo =
    Decode.map5 WeatherInfo
        (Decode.field "temperatureC" Decode.int)
        (Decode.field "condition" conditionDecoder)
        (Decode.maybe (Decode.field "humidityPercent" Decode.int))
        (Decode.maybe (Decode.field "pressureHpa" Decode.int))
        (Decode.maybe (Decode.field "windKph" Decode.int))


conditionDecoder : Decode.Decoder Condition
conditionDecoder =
    Decode.string
        |> Decode.map
            (\value ->
                case value of
                    "clear" ->
                        Clear

                    "cloudy" ->
                        Cloudy

                    "fog" ->
                        Fog

                    "drizzle" ->
                        Drizzle

                    "rain" ->
                        Rain

                    "snow" ->
                        Snow

                    "showers" ->
                        Showers

                    "storm" ->
                        Storm

                    _ ->
                        UnknownWeather
            )


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
