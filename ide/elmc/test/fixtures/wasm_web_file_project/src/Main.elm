module Main exposing (main)

import Browser
import File.Download as Download
import Html exposing (Html, text)


type Msg
    = Never


update : Msg -> () -> ( (), Cmd Msg )
update _ _ =
    ( (), Cmd.none )


view : () -> Html Msg
view _ =
    text "ok"


init : () -> ( (), Cmd Msg )
init _ =
    ( (), Download.string "draft.md" "text/plain" "hello" )


main : Program () () Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
