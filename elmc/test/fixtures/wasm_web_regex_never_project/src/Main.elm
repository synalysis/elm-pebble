module Main exposing (main)

import Html exposing (Html, text)
import Regex


main : Html String
main =
    if
        not (Regex.contains Regex.never "abc")
            && Regex.find Regex.never "abc"
            == []
    then
        text "ok"

    else
        text "fail"
