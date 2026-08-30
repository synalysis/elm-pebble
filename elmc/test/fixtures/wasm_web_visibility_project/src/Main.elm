module Main exposing (main)

import Browser
import Browser.Events exposing (Visibility(..))
import Html exposing (Html, text)


type alias Model =
    String


type Msg
    = Vis Visibility


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait", Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Vis Visible ->
            ( "visible", Cmd.none )

        Vis Hidden ->
            ( "hidden", Cmd.none )


view : Model -> Html Msg
view model =
    text model


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onVisibilityChange Vis


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
