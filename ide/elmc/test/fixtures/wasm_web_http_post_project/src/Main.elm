module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http


type Msg
    = Got (Result Http.Error String)


update : Msg -> () -> ( (), Cmd Msg )
update msg _ =
    case msg of
        Got (Ok body) ->
            ( (), Cmd.none )

        Got (Err _) ->
            ( (), Cmd.none )


view : () -> Html Msg
view _ =
    text "ok"


init : () -> ( (), Cmd Msg )
init _ =
    ( ()
    , Http.post
        { url = "https://example.com/api"
        , body = Http.emptyBody
        , expect = Http.expectString Got
        }
    )


main : Program () () Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
