module Main exposing (main)

import BackendTask.Http
import Browser
import Html exposing (Html, text)
import Json.Decode as Decode
import Task


type Msg
    = Got (Result String String)


update : Msg -> () -> ( (), Cmd Msg )
update msg _ =
    case msg of
        Got (Ok _) ->
            ( (), Cmd.none )

        Got (Err _) ->
            ( (), Cmd.none )


view : () -> Html Msg
view _ =
    text "ok"


init : () -> ( (), Cmd Msg )
init _ =
    ( ()
    , Task.attempt Got <|
        BackendTask.Http.getJson "https://example.com/data.json" Decode.string
    )


subscriptions : () -> Sub Msg
subscriptions _ =
    Sub.none


main : Program () () Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
