module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http


type Msg
    = Got (Result Http.Error String)


update : Msg -> () -> ( (), Cmd Msg )
update msg _ =
    case msg of
        Got _ ->
            ( (), Cmd.none )


view : () -> Html Msg
view _ =
    text "ok"


init : () -> ( (), Cmd Msg )
init _ =
    ( ()
    , Cmd.batch
        [ Http.get
            { url = "https://slow.example.com/data"
            , expect = Http.expectString Got
            , tracker = Just "upload"
            }
        , Http.cancel "upload"
        ]
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
