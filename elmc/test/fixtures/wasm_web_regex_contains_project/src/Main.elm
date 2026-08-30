module Main exposing (main)

import Html exposing (Html, text)
import Regex


main : Html String
main =
    case Regex.fromString "ab" of
        Nothing ->
            text "fail-re"

        Just re ->
            if Regex.contains re "xxabyy" && not (Regex.contains re "xxxx") then
                text "ok"

            else
                text "fail"
