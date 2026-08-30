module Main exposing (main)

import Browser
import Browser.Events
import Html exposing (Html, text)


type alias Model =
    String


type Msg
    = Resize Int Int


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait", Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Resize width height ->
            ( String.fromInt width ++ "x" ++ String.fromInt height, Cmd.none )


view : Model -> Html Msg
view model =
    text model


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onResize Resize


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
