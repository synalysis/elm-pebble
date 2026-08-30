module Main exposing (main)

import Html exposing (Html, text)


main : Html String
main =
    case ( Just 1, Nothing, Just 2, Just 3 ) of
        ( Just a, Nothing, Just b, Just c ) ->
            text (String.fromInt (a + b + c))

        _ ->
            text "fail"
