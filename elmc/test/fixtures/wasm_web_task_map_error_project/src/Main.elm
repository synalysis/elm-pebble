module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Task


type alias Model =
    { err : String
    , ok : String
    }


type Msg
    = GotErr (Result String Int)
    | GotOk (Result String Int)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotErr (Err err) ->
            ( { model | err = err }, Cmd.none )

        GotOk (Ok n) ->
            ( { model | ok = String.fromInt n }, Cmd.none )

        _ ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    text (model.err ++ "|" ++ model.ok)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { err = "wait", ok = "wait" }
    , Cmd.batch
        [ Task.fail "boom"
            |> Task.mapError (\e -> e ++ "!")
            |> Task.attempt GotErr
        , Task.succeed 7
            |> Task.mapError (\_ -> "nope")
            |> Task.attempt GotOk
        ]
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
