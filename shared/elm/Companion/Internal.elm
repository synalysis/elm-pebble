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
            0

        Berlin ->
            1

        Zurich ->
            2

        NewYork ->
            3


decodeLocationCode : Int -> Maybe Location
decodeLocationCode value =
    case value of
        0 ->
            Just CurrentLocation

        1 ->
            Just Berlin

        2 ->
            Just Zurich

        3 ->
            Just NewYork

        _ ->
            Nothing


encodeTutorialColorCode : TutorialColor -> Int
encodeTutorialColorCode value =
    case value of
        Black ->
            0

        White ->
            1

        Green ->
            2

        Blue ->
            3

        Yellow ->
            4


decodeTutorialColorCode : Int -> Maybe TutorialColor
decodeTutorialColorCode value =
    case value of
        0 ->
            Just Black

        1 ->
            Just White

        2 ->
            Just Green

        3 ->
            Just Blue

        4 ->
            Just Yellow

        _ ->
            Nothing


encodeWeatherConditionCode : WeatherCondition -> Int
encodeWeatherConditionCode value =
    case value of
        Clear ->
            0

        Cloudy ->
            1

        Fog ->
            2

        Drizzle ->
            3

        Rain ->
            4

        Snow ->
            5

        Showers ->
            6

        Storm ->
            7

        UnknownWeather ->
            8


decodeWeatherConditionCode : Int -> Maybe WeatherCondition
decodeWeatherConditionCode value =
    case value of
        0 ->
            Just Clear

        1 ->
            Just Cloudy

        2 ->
            Just Fog

        3 ->
            Just Drizzle

        4 ->
            Just Rain

        5 ->
            Just Snow

        6 ->
            Just Showers

        7 ->
            Just Storm

        8 ->
            Just UnknownWeather

        _ ->
            Nothing


encodeTemperatureTag : Temperature -> Int
encodeTemperatureTag value =
    case value of
        Celsius field1 ->
            0

        Fahrenheit field1 ->
            1


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
        0 ->
            Just (Celsius value)

        1 ->
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

        SetBackgroundColor field1 ->
            Encode.object
                [ ( "message_tag", Encode.int 203 )
                , ( "set_background_color_field1", Encode.int (encodeTutorialColorCode field1) )
                ]

        SetTextColor field1 ->
            Encode.object
                [ ( "message_tag", Encode.int 204 )
                , ( "set_text_color_field1", Encode.int (encodeTutorialColorCode field1) )
                ]

        SetShowDate field1 ->
            Encode.object
                [ ( "message_tag", Encode.int 205 )
                , ( "set_show_date_field1", Encode.int (if field1 then 1 else 0) )
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

