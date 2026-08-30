module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Process
import Task


type alias Model =
    String


type Msg
    = Got String


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Task.sequence
        [ Task.succeed 1
        , Process.sleep 8 |> Task.map (\_ -> 2)
        , Task.succeed 3
        ]
        |> Task.map (\xs -> String.join "," (List.map String.fromInt xs))
        |> Task.andThen
            (\ok ->
                Task.sequence
                    [ Task.succeed 1
                    , Task.fail 9
                    , Task.succeed 3
                    ]
                    |> Task.onError (\n -> Task.succeed (ok ++ ";err=" ++ String.fromInt n))
            )
        |> Task.perform Got
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got text ->
            ( text, Cmd.none )


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
