module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)


type alias Model =
    String


init : () -> ( Model, Cmd () )
init _ =
    ( "hello", Cmd.none )


update : () -> Model -> ( Model, Cmd () )
update _ _ =
    ( "clicked", Cmd.none )


view : Model -> Html ()
view model =
    div [] [ button [ onClick () ] [ text model ] ]


main : Program () Model ()
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
