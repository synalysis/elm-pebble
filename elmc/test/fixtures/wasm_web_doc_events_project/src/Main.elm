module Main exposing (main)

import Browser
import Browser.Events
import Html exposing (Html, text)
import Json.Decode as Decode


type alias Model =
    String


type Msg
    = Clicked Int
    | Key String


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait", Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Clicked _ ->
            ( if model == "wait" then
                "click"

              else
                model
            , Cmd.none
            )

        Key k ->
            ( if k == "a" && model == "click" then
                "ok"

              else
                model
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    text model


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Browser.Events.onClick (Decode.succeed (Clicked 1))
        , Browser.Events.onKeyDown (Decode.field "key" Decode.string |> Decode.map Key)
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
