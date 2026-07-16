module Main exposing (main)

import Browser
import Html exposing (Html, text)


type alias Model =
    Int


init : () -> Model
init _ =
    0


update : msg -> Model -> Model
update _ model =
    model


view : Model -> Html msg
view model =
    text ("count: " ++ String.fromInt model)


main : Program () Model msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
