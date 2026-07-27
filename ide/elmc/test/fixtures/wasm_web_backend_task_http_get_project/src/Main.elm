module Main exposing (main)

import BackendTask.Http
import Browser
import Html exposing (Html, text)
import Task


type alias Model =
    { body : Maybe String }


type Msg
    = Got (Result String String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Got (Ok body) ->
            ( { model | body = Just body }, Cmd.none )

        Got (Err _) ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    case model.body of
        Just body ->
            text body

        Nothing ->
            text "pending"


init : () -> ( Model, Cmd Msg )
init _ =
    ( { body = Nothing }
    , Task.attempt Got <|
        BackendTask.Http.get "https://example.com/hello.txt" BackendTask.Http.expectString
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
