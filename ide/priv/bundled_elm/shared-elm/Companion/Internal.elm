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
import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode


decodeListInt : String -> Decode.Decoder (List Int)
decodeListInt prefix =
    Decode.field (prefix ++ "_count") Decode.int
        |> Decode.andThen
            (\wireCount ->
                let
                    count =
                        wireCount - 1
                in
                if count < 0 then
                    Decode.fail "Invalid list count"
                else
                    decodeListIntElements prefix count 0 []
            )


decodeListIntElements : String -> Int -> Int -> List Int -> Decode.Decoder (List Int)
decodeListIntElements prefix remaining index acc =
    if remaining <= 0 then
        Decode.succeed (List.reverse acc)
    else
        Decode.oneOf
            [ Decode.field (prefix ++ "_" ++ String.fromInt index) Decode.int
                |> Decode.map (\wire -> wire - 1)
            , Decode.succeed 0
            ]
            |> Decode.andThen
                (\value ->
                    decodeListIntElements prefix (remaining - 1) (index + 1) (value :: acc)
                )


encodeListInt : String -> List Int -> List ( String, Encode.Value )
encodeListInt prefix list =
    let
        items =
            if List.length list > 16 then
                List.take 16 list
            else
                list
    in
    ( prefix ++ "_count", Encode.int (List.length items + 1) )
        :: List.indexedMap
            (\index value ->
                ( prefix ++ "_" ++ String.fromInt index, Encode.int (value + 1) )
            )
            items


decodeListBy : String -> (String -> Decode.Decoder a) -> Decode.Decoder (List a)
decodeListBy prefix decodeItem =
    Decode.field (prefix ++ "_count") Decode.int
        |> Decode.andThen
            (\wireCount ->
                let
                    count =
                        wireCount - 1
                in
                if count < 0 then
                    Decode.fail "Invalid list count"
                else
                    decodeListByElements prefix decodeItem count 0 []
            )


decodeListByElements : String -> (String -> Decode.Decoder a) -> Int -> Int -> List a -> Decode.Decoder (List a)
decodeListByElements prefix decodeItem remaining index acc =
    if remaining <= 0 then
        Decode.succeed (List.reverse acc)
    else
        decodeItem (prefix ++ "_" ++ String.fromInt index)
            |> Decode.andThen
                (\value ->
                    decodeListByElements prefix decodeItem (remaining - 1) (index + 1) (value :: acc)
                )


encodeListBy : String -> (String -> a -> List ( String, Encode.Value )) -> List a -> List ( String, Encode.Value )
encodeListBy prefix encodeItem list =
    let
        items =
            if List.length list > 16 then
                List.take 16 list
            else
                list
    in
    ( prefix ++ "_count", Encode.int (List.length items + 1) )
        :: (items
                |> List.indexedMap
                    (\index value ->
                        encodeItem (prefix ++ "_" ++ String.fromInt index) value
                    )
                |> List.concat
           )


decodeDictStringBy : String -> (String -> Decode.Decoder a) -> Decode.Decoder (Dict String a)
decodeDictStringBy prefix decodeValue =
    Decode.field (prefix ++ "_count") Decode.int
        |> Decode.andThen
            (\wireCount ->
                let
                    count =
                        wireCount - 1
                in
                if count < 0 then
                    Decode.fail "Invalid dict count"
                else
                    decodeDictStringByElements prefix decodeValue count 0 []
            )


decodeDictStringByElements : String -> (String -> Decode.Decoder a) -> Int -> Int -> List ( String, a ) -> Decode.Decoder (Dict String a)
decodeDictStringByElements prefix decodeValue remaining index acc =
    if remaining <= 0 then
        Decode.succeed (Dict.fromList (List.reverse acc))
    else
        Decode.map2 Tuple.pair
            (Decode.field (prefix ++ "_key_" ++ String.fromInt index) Decode.string)
            (decodeValue (prefix ++ "_val_" ++ String.fromInt index))
            |> Decode.andThen
                (\entry ->
                    decodeDictStringByElements prefix decodeValue (remaining - 1) (index + 1) (entry :: acc)
                )


encodeDictStringBy : String -> (String -> a -> List ( String, Encode.Value )) -> Dict String a -> List ( String, Encode.Value )
encodeDictStringBy prefix encodeValue dict =
    let
        entries =
            Dict.toList dict |> List.take 16
    in
    ( prefix ++ "_count", Encode.int (List.length entries + 1) )
        :: (entries
                |> List.indexedMap
                    (\index ( key, value ) ->
                        ( prefix ++ "_key_" ++ String.fromInt index, Encode.string key )
                            :: encodeValue (prefix ++ "_val_" ++ String.fromInt index) value
                    )
                |> List.concat
           )




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


encodeTutorialColorCode : TutorialColor -> Int
encodeTutorialColorCode value =
    case value of
        Black ->
            1

        White ->
            2

        Green ->
            3

        Blue ->
            4

        Yellow ->
            5


decodeTutorialColorCode : Int -> Maybe TutorialColor
decodeTutorialColorCode value =
    case value of
        1 ->
            Just Black

        2 ->
            Just White

        3 ->
            Just Green

        4 ->
            Just Blue

        5 ->
            Just Yellow

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
                ([ ( "message_tag", Encode.int 201 )
                , ( "provide_temperature_field1_tag", Encode.int (encodeTemperatureTag field1) )
                , ( "provide_temperature_field1_value", Encode.int (encodeTemperatureValue field1) ) ])

        ProvideCondition field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 202 )
                , ( "provide_condition_field1", Encode.int (encodeWeatherConditionCode field1) ) ])

        SetBackgroundColor field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 203 )
                , ( "set_background_color_field1", Encode.int (encodeTutorialColorCode field1) ) ])

        SetTextColor field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 204 )
                , ( "set_text_color_field1", Encode.int (encodeTutorialColorCode field1) ) ])

        SetShowDate field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 205 )
                , ( "set_show_date_field1", Encode.int (if field1 then 1 else 2) ) ])


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

