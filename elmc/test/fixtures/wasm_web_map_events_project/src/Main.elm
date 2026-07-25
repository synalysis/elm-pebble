module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)


type Msg
    = Outer Int


childView : Html Int
childView =
    button [ onClick 1 ] [ text "mapped click" ]


init : Int
init =
    0


update : Msg -> Int -> Int
update msg model =
    case msg of
        Outer n ->
            model + n


view : Int -> Html Msg
view model =
    div [] [ text ("count: " ++ String.fromInt model), Html.map Outer childView ]


main : Program () Int Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
