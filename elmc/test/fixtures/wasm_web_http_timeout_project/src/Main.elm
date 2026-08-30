module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http


type alias Model =
    String


type Msg
    = Got (Result Http.Error String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok _) ->
            ( "ok", Cmd.none )

        Got (Err Http.Timeout) ->
            ( "timeout", Cmd.none )

        Got (Err _) ->
            ( "err", Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Http.request
        { method = "GET"
        , headers = []
        , url = "https://example.com/slow"
        , body = Http.emptyBody
        , expect = Http.expectString Got
        , timeout = Just 50
        , tracker = Nothing
        }
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
