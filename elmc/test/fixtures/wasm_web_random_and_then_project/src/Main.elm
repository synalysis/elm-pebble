module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Random


type alias Model =
    String


type Msg
    = Got ( Int, String )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got ( n, label ) ->
            ( String.fromInt n ++ ":" ++ label, Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Random.generate Got
        (Random.int 3 3
            |> Random.andThen
                (\n ->
                    Random.pair (Random.constant n) (Random.uniform "a" [ "b" ])
                )
        )
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
