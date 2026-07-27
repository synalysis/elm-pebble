module Main exposing (main)

import BackendTask.Http
import Browser
import Html exposing (Html, text)
import Json.Decode as Decode
import Task


type alias Model =
    { stars : Maybe Int }


type Msg
    = Got (Result String Int)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Got (Ok stars) ->
            ( { model | stars = Just stars }, Cmd.none )

        Got (Err _) ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    case model.stars of
        Just stars ->
            text (String.fromInt stars)

        Nothing ->
            text "pending"


init : () -> ( Model, Cmd Msg )
init _ =
    ( { stars = Nothing }
    , Task.attempt Got <|
        BackendTask.Http.getWithOptions
            { url = "https://example.com/stars.json"
            , expect =
                BackendTask.Http.withMetadata
                    (\metadata n -> metadata.statusCode + n)
                    (BackendTask.Http.withMetadata
                        (\metadata n -> n * 10)
                        (BackendTask.Http.expectJson (Decode.field "stars" Decode.int))
                    )
            , headers = [ ( "X-Test-Header", "probe" ) ]
            , cacheStrategy = Just IgnoreCache
            , retries = Just 1
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
