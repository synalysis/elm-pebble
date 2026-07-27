module Main exposing (main)

import Html exposing (code, div, text)
import Html.Attributes exposing (class)


tag =
    code


main =
    div [ class "page" ]
        [ tag [ class "snippet" ] [ text "ok" ] ]
