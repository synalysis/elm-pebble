module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http
import Json.Encode as Encode


type alias Model =
    String


type Msg
    = Got (Result Http.Error String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok label) ->
            ( label, Cmd.none )

        Got (Err _) ->
            ( "err", Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Http.riskyRequest
        { method = "POST"
        , headers = []
        , url = "https://example.com/json"
        , body = Http.jsonBody (Encode.object [ ( "n", Encode.int 7 ) ])
        , expect = Http.expectString Got
        , timeout = Nothing
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
