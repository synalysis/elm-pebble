module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


main : Html String
main =
    case Decode.decodeString (Decode.field "missing" Decode.int) "{}" of
        Ok _ ->
            text "unexpected-ok"

        Err err ->
            text ("decode-error:" ++ Decode.errorToString err)
