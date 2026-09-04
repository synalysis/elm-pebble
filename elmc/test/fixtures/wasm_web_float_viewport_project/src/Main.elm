module Main exposing (main)

import Browser
import Html exposing (Html)
import Svg exposing (svg)
import Svg.Attributes exposing (height, viewBox, width)


type alias Vec2 =
    { x : Float, y : Float }


init : ()
init =
    ()


update : () -> () -> ()
update _ model =
    model


view : () -> Html ()
view _ =
    let
        lo =
            { x = 0, y = 0 }

        hi =
            { x = 656, y = 100 }

        w =
            String.fromFloat (hi.x - lo.x)

        h =
            String.fromFloat (hi.y - lo.y)
    in
    svg
        [ width w
        , height h
        , viewBox ("-2 -2 " ++ w ++ " " ++ h)
        ]
        []


main : Program () () ()
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
