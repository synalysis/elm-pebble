module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


main : Html String
main =
    case Decode.decodeString (Decode.keyValuePairs Decode.int) "{\"a\":1,\"b\":2}" of
        Ok pairs ->
            text
                (pairs
                    |> List.map (\( key, n ) -> key ++ ":" ++ String.fromInt n)
                    |> String.join ","
                )

        Err _ ->
            text "fail"
