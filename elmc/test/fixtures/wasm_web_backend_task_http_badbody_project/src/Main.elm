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

        Got (Err (BadBody _ msg)) ->
            ( { model | label = Just ("bad-body:" ++ msg) }, Cmd.none )

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
            { url = "https://example.com/broken.json"
            , expect = BackendTask.Http.expectJson (Decode.field "stars" Decode.int)
            , headers = []
            , cacheStrategy = Nothing
            , retries = Nothing
            , timeoutInMs = Nothing
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
