module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)


type Msg
    = Outer Int


childView : Html Int
childView =
    button [ onClick 1 ] [ text "mapped click" ]


init : () -> ( Int, Cmd Msg )
init _ =
    ( 0, Cmd.none )


update : Msg -> Int -> ( Int, Cmd Msg )
update msg model =
    case msg of
        Outer n ->
            ( model + n, Cmd.none )


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
