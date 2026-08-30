module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http
import Task


type alias Model =
    String


type Msg
    = Got (Result String String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok label) ->
            ( label, Cmd.none )

        Got (Err err) ->
            ( err, Cmd.none )


view : Model -> Html Msg
view model =
    text model


fromResponse : Http.Response String -> Result String String
fromResponse response =
    case response of
        Http.GoodStatus_ metadata body ->
            Ok
                (String.fromInt metadata.statusCode
                    ++ ":"
                    ++ metadata.statusText
                    ++ ":"
                    ++ body
                )

        Http.BadStatus_ metadata ->
            Err ("bad:" ++ String.fromInt metadata.statusCode)

        Http.BadUrl_ url ->
            Err ("url:" ++ url)

        Http.Timeout_ ->
            Err "timeout"

        Http.NetworkError_ ->
            Err "network"


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Http.task
        { method = "POST"
        , headers = [ Http.header "X-Token" "abc" ]
        , url = "https://example.com/string-task"
        , body = Http.stringBody "text/plain" "ping"
        , resolver = Http.stringResolver fromResponse
        , timeout = Nothing
        }
        |> Task.attempt Got
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
