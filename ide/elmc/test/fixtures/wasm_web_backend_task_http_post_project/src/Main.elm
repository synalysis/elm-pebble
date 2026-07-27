module Main exposing (main)

import BackendTask.Http
import Browser
import Html exposing (Html, text)
import Json.Encode as Encode
import Task


type alias Model =
    { posted : Bool }


type Msg
    = Got (Result String ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Got (Ok _) ->
            ( { model | posted = True }, Cmd.none )

        Got (Err _) ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    if model.posted then
        text "posted"

    else
        text "pending"


init : () -> ( Model, Cmd Msg )
init _ =
    ( { posted = False }
    , Task.attempt Got <|
        BackendTask.Http.post
            "https://example.com/submit"
            (BackendTask.Http.jsonBody <|
                Encode.object [ ( "name", Encode.string "test" ) ]
            )
            (BackendTask.Http.expectWhatever ())
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
