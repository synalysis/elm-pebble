module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http
import Task


type alias Model =
    String


type Msg
    = Got (Result Http.Error String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok body) ->
            ( body, Cmd.none )

        Got (Err _) ->
            ( "err", Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Http.task
        { method = "GET"
        , headers = []
        , url = "https://example.com/task"
        , body = Http.emptyBody
        , resolver = Http.stringResolver (\_ -> Ok "hello-task")
        , timeout = Nothing
        }
        |> Task.attempt Got
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
