module Main exposing (main)

import Browser
import Html exposing (Html)
import Svg exposing (svg)
import Svg.Attributes exposing (height, viewBox, width)

type alias Model = ()
init _ = ( (), Cmd.none )
update _ m = ( m, Cmd.none )

view : Model -> Html ()
view _ =
    let
        w =
            String.fromFloat (700 - 44)
    in
    svg [ width w, height w, viewBox w ] []

main = Browser.sandbox { init = init, update = update, view = view }
