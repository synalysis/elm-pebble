port module Main exposing (main)

import Browser
import Browser.Navigation
import Html exposing (Html, text)
import Url


port listen : (Int -> msg) -> Sub msg


type alias Model =
    Int


type Msg
    = Got Int


init : () -> ( Model, Cmd Msg )
init _ =
    ( 0, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got n ->
            ( n, Cmd.none )


view : Model -> Html Msg
view model =
    text (String.fromInt model)


subscriptions : Model -> Sub Msg
subscriptions _ =
    listen Got


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
