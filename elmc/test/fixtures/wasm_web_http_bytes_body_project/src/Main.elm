module Main exposing (main)

import Browser
import Bytes.Encode as Encode
import Html exposing (Html, text)
import Http


type alias Model =
    String


type Msg
    = Got (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok ()) ->
            ( "ok", Cmd.none )

        Got (Err _) ->
            ( "err", Cmd.none )


view : Model -> Html Msg
view model =
    text model


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Http.post
        { url = "https://example.com/bin"
        , body = Http.bytesBody "application/octet-stream" (Encode.encode (Encode.unsignedInt8 9))
        , expect = Http.expectWhatever Got
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
