module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)


type alias Model =
    String


init : Model
init =
    "hello"


update : () -> Model -> Model
update _ _ =
    "clicked"


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
