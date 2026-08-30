module Main exposing (main)

import Dict
import Html exposing (Html, text)
import Json.Decode as Decode


main : Html String
main =
    case Decode.decodeString (Decode.dict Decode.int) "{\"a\":1,\"b\":2}" of
        Ok decoded ->
            if decoded == Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ] then
                text "ok"

            else
                text "not-dict"

        Err _ ->
            text "fail"
