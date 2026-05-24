module Companion.Internal exposing
    ( decodeWatchToPhonePayload
    , encodePhoneToWatch
    , watchToPhoneTag
    , watchToPhoneValue
    )

{-| Generated wire encoding and decoding helpers for companion messages.

This module is derived from `Companion.Types`; edit the protocol types rather
than this file.
-}

import Companion.Types exposing (..)
import Json.Decode as Decode
import Json.Encode as Encode


encodeLocationCode : Location -> Int
encodeLocationCode value =
    case value of
        CurrentLocation ->
            1

        Berlin ->
            2

        Zurich ->
            3

        NewYork ->
            4


decodeLocationCode : Int -> Maybe Location
decodeLocationCode value =
    case value of
        1 ->
            Just CurrentLocation

        2 ->
            Just Berlin

        3 ->
            Just Zurich

        4 ->
            Just NewYork

        _ ->
            Nothing


encodeWeatherConditionCode : WeatherCondition -> Int
encodeWeatherConditionCode value =
    case value of
        Clear ->
            1

        Cloudy ->
            2

        Fog ->
            3

        Drizzle ->
            4

        Rain ->
            5

        Snow ->
            6

        Showers ->
            7

        Storm ->
            8

        UnknownWeather ->
            9


decodeWeatherConditionCode : Int -> Maybe WeatherCondition
decodeWeatherConditionCode value =
    case value of
        1 ->
            Just Clear

        2 ->
            Just Cloudy

        3 ->
            Just Fog

        4 ->
            Just Drizzle

        5 ->
            Just Rain

        6 ->
            Just Snow

        7 ->
            Just Showers

        8 ->
            Just Storm

        9 ->
            Just UnknownWeather

        _ ->
            Nothing


encodeTemperatureTag : Temperature -> Int
encodeTemperatureTag value =
    case value of
        Celsius field1 ->
            1

        Fahrenheit field1 ->
            2


encodeTemperatureValue : Temperature -> Int
encodeTemperatureValue value =
    case value of
        Celsius field1 ->
            field1

        Fahrenheit field1 ->
            field1


decodeTemperature : Int -> Int -> Maybe Temperature
decodeTemperature tag value =
    case tag of
        1 ->
            Just (Celsius value)

        2 ->
            Just (Fahrenheit value)

        _ ->
            Nothing


decodeWatchToPhonePayload : Decode.Value -> Result String WatchToPhone
decodeWatchToPhonePayload value =
    Decode.decodeValue (Decode.field "message_tag" Decode.int) value
        |> Result.mapError Decode.errorToString
        |> Result.andThen
            (\tag ->
                case tag of
                    2 ->
                        Decode.decodeValue (Decode.field "request_weather_field1" Decode.int) value
                            |> Result.mapError Decode.errorToString
                            |> Result.andThen
                                (\field1 ->
                                    case decodeLocationCode field1 of
                                            Just decodedField1 ->
                                                Ok (RequestWeather decodedField1)

                                            Nothing ->
                                                Err ("Unknown Location code: " ++ String.fromInt field1)

                                )

                    _ ->
                        Err ("Unknown message_tag: " ++ String.fromInt tag)
            )


encodePhoneToWatch : PhoneToWatch -> Encode.Value
encodePhoneToWatch msg =
    case msg of
        ProvideTemperature field1 ->
            Encode.object
                [ ( "message_tag", Encode.int 201 )
                , ( "provide_temperature_field1_tag", Encode.int (encodeTemperatureTag field1) )
                , ( "provide_temperature_field1_value", Encode.int (encodeTemperatureValue field1) )
                ]

        ProvideCondition field1 ->
            Encode.object
                [ ( "message_tag", Encode.int 202 )
                , ( "provide_condition_field1", Encode.int (encodeWeatherConditionCode field1) )
                ]


watchToPhoneTag : WatchToPhone -> Int
watchToPhoneTag message =
    case message of
        RequestWeather _ ->
            2


watchToPhoneValue : WatchToPhone -> Int
watchToPhoneValue message =
    case message of
        RequestWeather field1 ->
            encodeLocationCode field1

