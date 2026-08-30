module Main exposing (main)

import Browser
import Dict
import Html exposing (Html, text)
import Http


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
            let
                header =
                    metadata.headers
                        |> Dict.get "content-type"
                        |> Maybe.withDefault "?"
            in
            Ok
                (String.fromInt metadata.statusCode
                    ++ ":"
                    ++ metadata.statusText
                    ++ ":"
                    ++ metadata.url
                    ++ ":"
                    ++ header
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
    , Http.get
        { url = "https://example.com/resp"
        , expect = Http.expectStringResponse Got fromResponse
        }
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
