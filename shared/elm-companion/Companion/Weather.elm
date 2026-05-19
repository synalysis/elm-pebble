module Companion.Weather exposing (WeatherInfo, current, forecast, onWeather, subscribe)

{-| Platform-provided weather helpers for companion apps. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Weather as Weather


type alias WeatherInfo =
    Weather.WeatherInfo


current : Cmd msg
current =
    Weather.current "weather-current"
        |> Phone.sendBridgeCommand


forecast : Cmd msg
forecast =
    Weather.forecast "weather-forecast"
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Weather.subscribe "weather-subscribe"
        |> Phone.sendBridgeCommand


onWeather : (Result String (List WeatherInfo) -> msg) -> Sub msg
onWeather toMsg =
    Phone.onRawMessage (decodeWeather >> toMsg)


decodeWeather : Decode.Value -> Result String (List WeatherInfo)
decodeWeather value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Weather.decode event of
                Weather.Current info ->
                    Ok [ info ]

                Weather.Forecast values ->
                    Ok values

                Weather.Error error ->
                    Err error

                Weather.Unknown eventName ->
                    Err ("Unexpected weather event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
