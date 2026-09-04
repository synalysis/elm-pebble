module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Process
import Task
import Time


type alias Model =
    String


type Msg
    = Got Time.Posix


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Process.sleep 5.0
        |> Task.andThen (\_ -> Time.now)
        |> Task.perform Got
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got posix ->
            ( String.fromInt (Time.posixToMillis posix), Cmd.none )


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
