module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http


type Msg
    = Got String


update : Msg -> () -> ( (), Cmd Msg )
update _ _ =
    ( (), Cmd.none )


view : () -> Html Msg
view _ =
    text "ok"


init : () -> ( (), Cmd Msg )
init _ =
    ( (), Http.get { url = "https://example.com", expect = Http.expectString Got } )


main : Program () () Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
