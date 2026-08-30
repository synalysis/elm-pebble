module Main exposing (main)

import Browser
import Bytes exposing (Endianness(..))
import Html exposing (Html, text)
import Task


type alias Model =
    String


type Msg
    = Got Endianness


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait", Task.perform Got Bytes.getHostEndianness )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got LE ->
            ( "le", Cmd.none )

        Got BE ->
            ( "be", Cmd.none )


view : Model -> Html Msg
view model =
    text model


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
