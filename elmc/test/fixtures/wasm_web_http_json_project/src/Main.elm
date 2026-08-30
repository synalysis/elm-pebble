module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http
import Json.Decode as Decode


type alias Model =
    String


type Msg
    = Got (Result Http.Error Int)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok n) ->
            ( String.fromInt n, Cmd.none )

        Got (Err _) ->
            ( "err", Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Http.get
        { url = "https://example.com/n"
        , expect = Http.expectJson Got (Decode.field "n" Decode.int)
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
