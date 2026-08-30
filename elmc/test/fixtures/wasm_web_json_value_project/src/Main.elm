module Main exposing (main)

import Array
import Html exposing (Html, text)
import Json.Decode as Decode
import Json.Encode as Encode


main : Html String
main =
    let
        valueOk =
            case Decode.decodeString Decode.value "{\"a\":1}" of
                Ok raw ->
                    case Decode.decodeValue (Decode.field "a" Decode.int) raw of
                        Ok 1 ->
                            Encode.encode 0 raw == "{\"a\":1}"

                        _ ->
                            False

                Err _ ->
                    False

        arrayOk =
            case Decode.decodeString (Decode.array Decode.int) "[10,20]" of
                Ok arr ->
                    Array.length arr == 2 && Array.get 1 arr == Just 20

                Err _ ->
                    False
    in
    if valueOk && arrayOk then
        text "ok"

    else
        text "fail"
