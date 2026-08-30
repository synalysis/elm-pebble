module Main exposing (main)

import Browser
import Browser.Dom
import Html exposing (Html, text)
import Task


type alias Model =
    String


type Msg
    = Got (Result Browser.Dom.Error ())


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Browser.Dom.focus "missing"
        |> Task.onError (\_ -> Browser.Dom.focus "box")
        |> Task.andThen (\_ -> Browser.Dom.blur "box")
        |> Task.attempt Got
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok ()) ->
            ( "ok", Cmd.none )

        Got (Err _) ->
            ( "missing", Cmd.none )


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
