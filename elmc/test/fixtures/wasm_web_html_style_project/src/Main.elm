module Main exposing (main)

import Browser
import Html exposing (Html, div, text)
import Html.Attributes exposing (id, style)


main : Program () () msg
main =
    Browser.sandbox
        { init = ()
        , update = \_ model -> model
        , view = view
        }


view : () -> Html msg
view _ =
    div
        [ id "box"
        , style "color" "red"
        , style "font-size" "12px"
        ]
        [ text "styled" ]
