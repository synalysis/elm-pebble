module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode
import Json.Encode as Encode


main : Html String
main =
    let
        decoded =
            Decode.decodeString Decode.int "42"

        encoded =
            Encode.encode 0 (Encode.object [ ( "x", Encode.int 1 ) ])
    in
    case decoded of
        Ok n ->
            text ("int:" ++ String.fromInt n ++ " json:" ++ encoded)

        Err _ ->
            text "decode failed"
