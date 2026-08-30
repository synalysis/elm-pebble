module Main exposing (main)

import Browser
import Browser.Dom
import Html exposing (Html, text)


init : () -> ( String, Cmd msg )
init _ =
    ( "ok", Browser.Dom.setTitle "hello-title" )


update : msg -> String -> ( String, Cmd msg )
update _ model =
    ( model, Cmd.none )


view : String -> Html msg
view model =
    text model


main : Program () String msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
