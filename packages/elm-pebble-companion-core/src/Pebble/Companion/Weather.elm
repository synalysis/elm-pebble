module Pebble.Companion.Weather exposing (Condition(..), Event(..), WeatherInfo, conditionDecoder, current, decode, forecast, subscribe)

{-| Weather snapshots exposed by the Pebble companion bridge.

This module models platform-provided weather data. Generic HTTP fetching remains
the responsibility of `elm/http`.

# Types
@docs Condition, WeatherInfo, Event

# Commands
@docs current, forecast, subscribe

# Events
@docs decode, conditionDecoder

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


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


{-| Weather events emitted by the companion bridge.
-}
type Event
    = Current WeatherInfo
    | Forecast (List WeatherInfo)
    | Error String
    | Unknown String


{-| Request current weather conditions.
-}
current : String -> CommandEnvelope
current id =
    Command.command id "weather" "current"


{-| Request forecast weather snapshots.
-}
forecast : String -> CommandEnvelope
forecast id =
    Command.command id "weather" "forecast"


{-| Subscribe to weather updates when supported.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "weather" "subscribe"


{-| Decode a pushed weather bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "weather.current" ->
            case Decode.decodeValue decodeWeatherInfo bridgeEvent.payload of
                Ok info ->
                    Current info

                Err error ->
                    Error (Decode.errorToString error)

        "weather.forecast" ->
            case Decode.decodeValue (Decode.field "forecast" (Decode.list decodeWeatherInfo)) bridgeEvent.payload of
                Ok values ->
                    Forecast values

                Err error ->
                    Error (Decode.errorToString error)

        "weather.error" ->
            Error (decodeErrorMessage bridgeEvent.payload "Weather unavailable")

        other ->
            Unknown other


decodeWeatherInfo : Decode.Decoder WeatherInfo
decodeWeatherInfo =
    Decode.map5 WeatherInfo
        (Decode.field "temperatureC" Decode.int)
        (Decode.field "condition" conditionDecoder)
        (Decode.maybe (Decode.field "humidityPercent" Decode.int))
        (Decode.maybe (Decode.field "pressureHpa" Decode.int))
        (Decode.maybe (Decode.field "windKph" Decode.int))


{-| Decode a string weather condition into the typed `Condition`.
-}
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
