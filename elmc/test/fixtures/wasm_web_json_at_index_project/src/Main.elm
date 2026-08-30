module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


show : Result Decode.Error String -> String
show result =
    case result of
        Ok s ->
            s

        Err _ ->
            "err"


main : Html String
main =
    text
        (String.join "|"
            [ show
                (Decode.decodeString
                    (Decode.at [ "user", "name" ] Decode.string)
                    "{\"user\":{\"name\":\"ada\"}}"
                )
            , show
                (Decode.decodeString
                    (Decode.index 1 Decode.int |> Decode.map String.fromInt)
                    "[10,20,30]"
                )
            , show
                (Decode.decodeString
                    (Decode.at [ "0" ] Decode.int |> Decode.map String.fromInt)
                    "{\"0\":7}"
                )
            , show
                (Decode.decodeString
                    (Decode.at [ "0" ] Decode.int |> Decode.map String.fromInt)
                    "[7]"
                )
            ]
        )
