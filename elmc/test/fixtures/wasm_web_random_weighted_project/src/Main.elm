module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Random


type alias Model =
    String


type Msg
    = Got Int


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got n ->
            ( String.fromInt n, Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Random.generate Got
        (Random.independentSeed
            |> Random.andThen
                (\seed ->
                    let
                        ( n, _ ) =
                            Random.step (Random.weighted ( 1, 9 ) [ ( 0, 0 ) ]) seed
                    in
                    Random.constant n
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
