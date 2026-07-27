module Main exposing (main)

import Browser
import Html exposing (Html)
import Svg exposing (rect, svg)
import Svg.Attributes exposing (fill, height, width, x, y)


type alias Model =
    ()


init : Model
init =
    ()


update : () -> Model -> Model
update _ model =
    model


view : Model -> Html ()
view _ =
    svg [ width "100", height "100" ] [ rect [ x "10", y "10", width "80", height "80", fill "red" ] [] ]


main : Program () Model ()
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
