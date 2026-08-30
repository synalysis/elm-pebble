module Main exposing (main)

import Html exposing (Html, text)


pick2 : Maybe Int -> Maybe String -> String
pick2 a b =
    case ( a, b ) of
        ( Just x, Nothing ) ->
            String.fromInt x

        _ ->
            "miss"


pick3 : Maybe Int -> Maybe String -> Maybe Int -> String
pick3 a b c =
    case ( a, b, c ) of
        ( Just x, Nothing, Just y ) ->
            String.fromInt x ++ ":" ++ String.fromInt y

        _ ->
            "miss"


main : Html String
main =
    text
        (String.join "|"
            [ pick2 (Just 4) Nothing
            , pick2 (Just 4) (Just "x")
            , pick3 (Just 1) Nothing (Just 2)
            , pick3 (Just 1) (Just "x") (Just 2)
            , pick3 Nothing Nothing (Just 2)
            ]
        )
