module Main exposing (main)

import Browser
import Bytes
import Bytes.Decode as Decode
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


fromResponse : Http.Response Bytes.Bytes -> Result String String
fromResponse response =
    case response of
        Http.GoodStatus_ metadata body ->
            case Decode.decode Decode.unsignedInt8 body of
                Just n ->
                    Ok
                        (String.fromInt metadata.statusCode
                            ++ ":"
                            ++ metadata.statusText
                            ++ ":"
                            ++ String.fromInt n
                            ++ ":"
                            ++ String.fromInt (Bytes.width body)
                        )

                Nothing ->
                    Err "decode"

        Http.BadStatus_ metadata _ ->
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
        { url = "https://example.com/bytes-resp"
        , expect = Http.expectBytesResponse Got fromResponse
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
