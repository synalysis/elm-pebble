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


decodePoint : String -> Decode.Decoder Point
decodePoint prefix =
    Decode.map2 (\x -> (\y -> { x = x, y = y }))
        (Decode.field (prefix ++ "_x") Decode.int)
        (Decode.field (prefix ++ "_y") Decode.int)


decodePointOffset : String -> Decode.Decoder Point
decodePointOffset prefix =
    Decode.map2 (\x -> (\y -> { x = x, y = y }))
        (Decode.field (prefix ++ "_x") Decode.int |> Decode.map (\wire -> wire - 1))
        (Decode.field (prefix ++ "_y") Decode.int |> Decode.map (\wire -> wire - 1))


encodePoint : String -> Point -> List ( String, Encode.Value )
encodePoint prefix value =
    [ ( (prefix ++ "_x"), Encode.int value.x ) ]
        ++ [ ( (prefix ++ "_y"), Encode.int value.y ) ]


encodePointOffset : String -> Point -> List ( String, Encode.Value )
encodePointOffset prefix value =
    [ ( (prefix ++ "_x"), Encode.int (value.x + 1) ) ]
        ++ [ ( (prefix ++ "_y"), Encode.int (value.y + 1) ) ]


encodeColorCode : Color -> Int
encodeColorCode value =
    case value of
        Red ->
            1

        Green ->
            2

        Blue ->
            3


decodeColorCode : Int -> Maybe Color
decodeColorCode value =
    case value of
        1 ->
            Just Red

        2 ->
            Just Green

        3 ->
            Just Blue

        _ ->
            Nothing


encodeMeasureTag : Measure -> Int
encodeMeasureTag value =
    case value of
        Liters field1 ->
            1

        Pounds field1 ->
            2


encodeMeasureValue : Measure -> Int
encodeMeasureValue value =
    case value of
        Liters field1 ->
            field1

        Pounds field1 ->
            field1


decodeMeasure : Int -> Int -> Maybe Measure
decodeMeasure tag value =
    case tag of
        1 ->
            Just (Liters value)

        2 ->
            Just (Pounds value)

        _ ->
            Nothing


decodeMeasureWatchScalar : String -> Decode.Decoder Measure
decodeMeasureWatchScalar prefix =
    Decode.field (prefix ++ "_tag") Decode.int
        |> Decode.andThen
            (\tag ->
                case decodeMeasure tag 0 of
                    Just decoded ->
                        Decode.succeed decoded

                    Nothing ->
                        Decode.fail ("Unknown Measure tag: " ++ String.fromInt tag)
            )


decodeMeasureLegacyWire : String -> Decode.Decoder Measure
decodeMeasureLegacyWire prefix =
    Decode.field (prefix ++ "_tag") Decode.int
        |> Decode.andThen
            (\tag ->
                Decode.field (prefix ++ "_value") Decode.int
                    |> Decode.andThen
                        (\wireValue ->
                            case decodeMeasure tag wireValue of
                                Just decoded ->
                                    Decode.succeed decoded

                                Nothing ->
                                    Decode.fail ("Unknown Measure tag/value")
                        )
            )


decodeWatchToPhonePayload : Decode.Value -> Result String WatchToPhone
decodeWatchToPhonePayload value =
    Decode.decodeValue (Decode.field "message_tag" Decode.int) value
        |> Result.mapError Decode.errorToString
        |> Result.andThen
            (\tag ->
                case tag of
                    2 ->
                        Ok Ping

                    3 ->
                        Decode.decodeValue (Decode.field "send_color_field1" Decode.int) value
                            |> Result.mapError Decode.errorToString
                            |> Result.andThen
                                (\field1 ->
                                    case decodeColorCode field1 of
                                            Just decodedField1 ->
                                                Ok (SendColor decodedField1)

                                            Nothing ->
                                                Err ("Unknown Color code: " ++ String.fromInt field1)

                                )

                    4 ->
                        Decode.decodeValue (decodeMeasureWatchScalar "send_measure_field1") value
                            |> Result.mapError Decode.errorToString
                            |> Result.andThen
                                (\field1 ->
                                    Ok (SendMeasure field1)
                                )

                    5 ->
                        Decode.decodeValue (decodePoint "send_point_field1") value
                            |> Result.mapError Decode.errorToString
                            |> Result.andThen
                                (\field1 ->
                                    Ok (SendPoint field1)
                                )

                    6 ->
                        Decode.decodeValue (decodeListInt "send_counts_field1") value
                            |> Result.mapError Decode.errorToString
                            |> Result.andThen
                                (\field1 ->
                                    Ok (SendCounts field1)
                                )

                    7 ->
                        Ok RequestPhoneExtras

                    _ ->
                        Err ("Unknown message_tag: " ++ String.fromInt tag)
            )


encodePhoneToWatch : PhoneToWatch -> Encode.Value
encodePhoneToWatch msg =
    case msg of
        Pong ->
            Encode.object
                ([ ( "message_tag", Encode.int 201 ) ])

        EchoColor field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 202 )
                 , ( "echo_color_field1", Encode.int (encodeColorCode field1) )
                 ] )

        EchoMeasure field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 203 )
                 , ( "echo_measure_field1_tag", Encode.int (encodeMeasureTag field1) )
                 , ( "echo_measure_field1_value", Encode.int (encodeMeasureValue field1) )
                 ] )

        EchoPoint field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 204 ) ]
                        ++ encodePoint "echo_point_field1" field1)

        EchoCounts field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 205 ) ]
                        ++ encodeListInt "echo_counts_field1" field1)

        PushBool field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 206 )
                 , ( "push_bool_field1", Encode.int (if field1 then 1 else 2) )
                 ] )

        PushString field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 207 )
                 , ( "push_string_field1", Encode.string field1 )
                 ] )

        PushPoints field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 208 ) ]
                        ++ encodeListBy "push_points_field1" (\itemPrefix itemValue -> encodePointOffset itemPrefix itemValue) field1)

        PushLabels field1 ->
            Encode.object
                ([ ( "message_tag", Encode.int 209 ) ]
                        ++ encodeDictStringBy "push_labels_field1" (\valuePrefix dictValue -> [ ( valuePrefix, Encode.int (dictValue + 1) ) ]) field1)


watchToPhoneTag : WatchToPhone -> Int
watchToPhoneTag message =
    case message of
        Ping ->
            2

        SendColor _ ->
            3

        SendMeasure _ ->
            4

        SendPoint _ ->
            5

        SendCounts _ ->
            6

        RequestPhoneExtras ->
            7


watchToPhoneValue : WatchToPhone -> Int
watchToPhoneValue message =
    case message of
        Ping ->
            0

        SendColor field1 ->
            encodeColorCode field1

        SendMeasure field1 ->
            encodeMeasureTag field1

        SendPoint field1 ->
            0

        SendCounts field1 ->
            0

        RequestPhoneExtras ->
            0
