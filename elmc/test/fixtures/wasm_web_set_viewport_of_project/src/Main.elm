module Main exposing (main)

import Browser
import Browser.Dom
import Html exposing (Html, text)
import Task


type alias Model =
    String


type Msg
    = Got (Result Browser.Dom.Error Browser.Dom.Viewport)


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Browser.Dom.setViewportOf "box" 7.0 8.0
        |> Task.andThen (\_ -> Browser.Dom.getViewportOf "box")
        |> Task.attempt Got
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok vp) ->
            ( n vp.viewport.x ++ "," ++ n vp.viewport.y, Cmd.none )

        Got (Err _) ->
            ( "missing", Cmd.none )


n : Float -> String
n value =
    String.fromInt (round value)


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
