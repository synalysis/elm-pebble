module Main exposing (main)

import BackendTask.Http exposing (Error(..))
import Browser
import Html exposing (Html, text)
import Json.Decode as Decode
import Task


type alias Model =
    { label : Maybe String }


type Msg
    = Got (Result BackendTask.Http.Error Int)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Got (Ok _) ->
            ( { model | label = Just "unexpected-ok" }, Cmd.none )

        Got (Err Timeout) ->
            ( { model | label = Just "timeout" }, Cmd.none )

        Got (Err _) ->
            ( { model | label = Just "other-error" }, Cmd.none )


view : Model -> Html Msg
view model =
    case model.label of
        Just label ->
            text label

        Nothing ->
            text "pending"


init : () -> ( Model, Cmd Msg )
init _ =
    ( { label = Nothing }
    , Task.attempt Got <|
        BackendTask.Http.getWithOptions
            { url = "https://example.com/slow.json"
            , expect = BackendTask.Http.expectJson (Decode.field "n" Decode.int)
            , headers = []
            , cacheStrategy = Nothing
            , retries = Nothing
            , timeoutInMs = Just 50
            , cachePath = Nothing
            }
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
