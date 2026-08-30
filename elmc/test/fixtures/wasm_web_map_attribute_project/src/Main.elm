module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes as Attr
import Html.Events exposing (onClick)


type Msg
    = Outer Int


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
    div []
        [ text ("count: " ++ String.fromInt model)
        , button [ Attr.map Outer (onClick 1) ] [ text "mapped attr" ]
        ]


main : Program () Int Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
