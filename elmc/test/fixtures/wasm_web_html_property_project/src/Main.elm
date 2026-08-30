module Main exposing (main)

import Html exposing (Html, input)
import Html.Attributes exposing (checked, disabled, hidden, value)


main : Html msg
main =
    input [ checked True, disabled False, hidden True, value "hi" ] []
