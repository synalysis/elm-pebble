module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http
import Process
import Task


type alias Model =
    String


type Msg
    = Tick
    | Killed


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Cmd.batch
        [ Process.sleep 40
            |> Task.perform (\_ -> Tick)
        , Process.spawn
            (Http.task
                { method = "GET"
                , headers = []
                , url = "https://hang.example/slow"
                , body = Http.emptyBody
                , resolver = Http.stringResolver (\_ -> Ok "leaked")
                , timeout = Nothing
                }
            )
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

        Tick ->
            ( "ok", Cmd.none )


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
