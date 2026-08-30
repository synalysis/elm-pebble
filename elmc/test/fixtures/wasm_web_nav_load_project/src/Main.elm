module Main exposing (main)

import Browser
import Browser.Navigation
import Html exposing (Html, text)


init : () -> ( String, Cmd msg )
init _ =
    ( "ok", Browser.Navigation.load "https://example.com/next" )


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
