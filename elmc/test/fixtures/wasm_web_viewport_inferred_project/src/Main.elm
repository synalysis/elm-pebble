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
    ( "wait", Task.attempt Got Browser.Dom.getViewport )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok vp) ->
            ( formatScene vp.scene ++ "@" ++ formatRect vp.viewport, Cmd.none )

        Got (Err _) ->
            ( "missing", Cmd.none )


formatScene scene =
    n scene.width ++ "x" ++ n scene.height


formatRect rect =
    n rect.x ++ "," ++ n rect.y ++ ":" ++ n rect.width ++ "x" ++ n rect.height


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
