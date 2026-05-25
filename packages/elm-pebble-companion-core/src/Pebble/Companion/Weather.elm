module Pebble.Companion.Weather exposing
    ( Condition(..)
    , WeatherInfo
    , WeatherUpdate(..)
    , current
    , forecast
    , onWeather
    , onCurrent
    , onForecast
    )

{-| Platform-provided weather for companion apps.

Weather is supplied by the companion bridge:

- In the **IDE debugger**, values come from simulator settings. These functions do not take a city name or other query parameters.
- On a **phone**, the bridge fetches live data over **HTTP** (Open-Meteo) using the device location from geolocation. Apps still do not pass a city name or other query string to `current` or `forecast`.

Use `current`, `forecast`, and `onWeather` directly — no separate registration commands.

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

Registers bridge handlers needed for weather command responses and push updates.
-}
current : (Result String WeatherInfo -> msg) -> Cmd msg
current toMsg =
    Cmd.batch
        [ Platform.setup weatherPushInterest
        , Platform.setup weatherCurrentInterest
        , Phone.send toMsg <|
            Phone.request "weather-current" "weather" "current" decodeCurrentResponse
        ]


{-| Request forecast snapshots from the platform weather service.

Registers the bridge handler needed for forecast command responses.
-}
forecast : (Result String (List WeatherInfo) -> msg) -> Cmd msg
forecast toMsg =
    Cmd.batch
        [ Platform.setup weatherForecastInterest
        , Phone.send toMsg <|
            Phone.request "weather-forecast" "weather" "forecast" decodeForecastResponse
        ]


{-| Receive pushed weather updates from the companion bridge.

Pair with `current` (or `forecast`) in `init` so the bridge registers interest and
can deliver pushed updates. Calling `current` also sends the bridge subscribe
operation for ongoing weather events.
-}
onWeather : (Result String WeatherUpdate -> msg) -> Sub msg
onWeather toMsg =
    Platform.subscribe (handler toMsg)


{-| Receive current-weather command responses on the dedicated weather port.

Pair with `current` in `init` so command responses are routed to this handler.
-}
onCurrent : (Result String WeatherInfo -> msg) -> Sub msg
onCurrent toMsg =
    Platform.subscribe (handlerCurrent toMsg)


{-| Receive forecast command responses on the dedicated weather port.

Pair with `forecast` in `init` so command responses are routed to this handler.
-}
onForecast : (Result String (List WeatherInfo) -> msg) -> Sub msg
onForecast toMsg =
    Platform.subscribe (handlerForecast toMsg)


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
