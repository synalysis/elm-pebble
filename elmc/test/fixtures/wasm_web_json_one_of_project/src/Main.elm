module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


tagged : Decode.Decoder String
tagged =
    Decode.oneOf
        [ Decode.int
            |> Decode.andThen
                (\n ->
                    if n >= 0 then
                        Decode.succeed ("i:" ++ String.fromInt n)

                    else
                        Decode.fail "neg"
                )
        , Decode.string |> Decode.map (\s -> "s:" ++ s)
        ]


show : Result Decode.Error String -> String
show result =
    case result of
        Ok s ->
            s

        Err _ ->
            "err"


maybeShow : Result Decode.Error (Maybe Int) -> String
maybeShow result =
    case result of
        Ok (Just n) ->
            "just:" ++ String.fromInt n

        Ok Nothing ->
            "nothing"

        Err _ ->
            "err"


main : Html String
main =
    text
        (String.join "|"
            [ show (Decode.decodeString tagged "1")
            , show (Decode.decodeString tagged "\"x\"")
            , show (Decode.decodeString tagged "true")
            , show (Decode.decodeString tagged "-3")
            , maybeShow (Decode.decodeString (Decode.maybe Decode.int) "null")
            , maybeShow (Decode.decodeString (Decode.maybe Decode.int) "true")
            , maybeShow (Decode.decodeString (Decode.maybe Decode.int) "4")
            , maybeShow (Decode.decodeString (Decode.nullable Decode.int) "null")
            , maybeShow (Decode.decodeString (Decode.nullable Decode.int) "5")
            , maybeShow (Decode.decodeString (Decode.nullable Decode.int) "true")
            , show (Decode.decodeString (Decode.lazy (\_ -> Decode.int) |> Decode.map (\n -> "lazy:" ++ String.fromInt n)) "9")
            ]
        )
