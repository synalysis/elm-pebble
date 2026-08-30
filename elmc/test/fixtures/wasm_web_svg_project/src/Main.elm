module Main exposing (main)

import Browser
import Html exposing (Html)
import Svg exposing (image, rect, svg, text, text_)
import Svg.Attributes as SA exposing (fill, height, width, x, xlinkHref, y)
import Svg.Keyed as Keyed


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
    svg [ width "100", height "100" ]
        [ rect [ x "10", y "10", width "80", height "80", fill "red" ] []
        , image [ xlinkHref "https://example.com/a.png", width "10", height "10" ] []
        , Keyed.node "g"
            [ SA.id "keyed" ]
            [ ( "a", text_ [ SA.xmlSpace "preserve" ] [ text "A" ] )
            , ( "b", text_ [] [ text "B" ] )
            ]
        ]


main : Program () Model ()
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
