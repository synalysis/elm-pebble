module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Time


type alias Model =
    Int


init : () -> ( Model, Cmd msg )
init _ =
    ( 0, Cmd.none )


type Msg
    = Tick Int


update : Msg -> Model -> ( Model, Cmd msg )
update (Tick n) _ =
    ( n, Cmd.none )


view : Model -> Html Msg
view model =
    text (String.fromInt model)


subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 100 Tick


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
