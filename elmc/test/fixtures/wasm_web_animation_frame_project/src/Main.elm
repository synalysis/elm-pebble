module Main exposing (main)

import Browser
import Browser.Events
import Html exposing (Html, text)
import Time


type alias Model =
    String


type Msg
    = Frame Time.Posix
    | Delta Float


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait", Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Frame posix ->
            if Time.posixToMillis posix > 0 then
                ( if model == "d" || model == "ok" then
                    "ok"

                  else
                    "f"
                , Cmd.none
                )

            else
                ( model, Cmd.none )

        Delta d ->
            if d > 0 then
                ( if model == "f" || model == "ok" then
                    "ok"

                  else
                    "d"
                , Cmd.none
                )

            else
                ( model, Cmd.none )


view : Model -> Html Msg
view model =
    text model


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onAnimationFrame Frame
        , Browser.Events.onAnimationFrameDelta Delta
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
