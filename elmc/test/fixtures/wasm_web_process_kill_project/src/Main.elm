module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Process
import Task
import Time


type alias Model =
    String


type Msg
    = Tick Int
    | Killed


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Cmd.batch
        [ Process.sleep 40
            |> Task.andThen (\_ -> Time.now)
            |> Task.map Time.posixToMillis
            |> Task.perform Tick
        , Process.spawn (Process.sleep 5000)
            |> Task.andThen
                (\id ->
                    Process.sleep 5
                        |> Task.andThen (\_ -> Process.kill id)
                )
            |> Task.perform (\_ -> Killed)
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Killed ->
            ( model, Cmd.none )

        Tick millis ->
            ( String.fromInt millis, Cmd.none )


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
