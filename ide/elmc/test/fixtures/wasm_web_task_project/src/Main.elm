module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Task
import Time


type alias Model =
    Int


init : () -> ( Model, Cmd Msg )
init _ =
    ( 0, Task.perform Tick Time.now )


type Msg
    = Tick Int


update : Msg -> Model -> ( Model, Cmd Msg )
update (Tick millis) _ =
    ( millis, Cmd.none )


view : Model -> Html Msg
view model =
    text (String.fromInt model)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
