module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Task
import Time


type Inner
    = Tick Int


type Msg
    = Wrapped Inner


update : Msg -> String -> ( String, Cmd Msg )
update msg _ =
    case msg of
        Wrapped (Tick _) ->
            ( "mapped", Cmd.none )


view : String -> Html Msg
view model =
    text model


init : () -> ( String, Cmd Msg )
init _ =
    ( "pending", Cmd.map Wrapped (Task.perform Tick Time.now) )


main : Program () String Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
