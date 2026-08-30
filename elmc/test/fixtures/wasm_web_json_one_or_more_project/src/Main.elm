module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


pair : Decode.Decoder String
pair =
    Decode.oneOrMore
        (\first rest ->
            String.fromInt first ++ ":" ++ String.fromInt (List.length rest)
        )
        Decode.int


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
            [ show (Decode.decodeString pair "[1,2,3]")
            , show (Decode.decodeString pair "[7]")
            , show (Decode.decodeString pair "[]")
            , show (Decode.decodeString pair "1")
            ]
        )
