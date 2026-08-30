module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Task
import Time


type alias Model =
    String


type Msg
    = Got Time.ZoneName


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait", Task.perform Got Time.getZoneName )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Time.Name name) ->
            ( "name:" ++ name, Cmd.none )

        Got (Time.Offset minutes) ->
            ( "offset:" ++ String.fromInt minutes, Cmd.none )


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
