module Main exposing (main)

import Browser
import Bytes.Decode as Decode
import Bytes.Encode as Encode
import Html exposing (Html, text)
import Http


type alias Model =
    { byte : String
    , unit : String
    }


type Msg
    = GotByte (Result Http.Error Int)
    | GotUnit (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotByte (Ok n) ->
            ( { model | byte = String.fromInt n }, Cmd.none )

        GotByte (Err _) ->
            ( { model | byte = "err" }, Cmd.none )

        GotUnit (Ok ()) ->
            ( { model | unit = "ok" }, Cmd.none )

        GotUnit (Err _) ->
            ( { model | unit = "err" }, Cmd.none )


view : Model -> Html Msg
view model =
    text (model.byte ++ "|" ++ model.unit)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { byte = "wait", unit = "wait" }
    , Cmd.batch
        [ Http.get
            { url = "https://example.com/bytes"
            , expect = Http.expectBytes GotByte Decode.unsignedInt8
            }
        , Http.post
            { url = "https://example.com/upload"
            , body =
                Http.multipartBody
                    [ Http.stringPart "name" "ada"
                    , Http.bytesPart "bin"
                        "application/octet-stream"
                        (Encode.encode (Encode.unsignedInt8 9))
                    ]
            , expect = Http.expectWhatever GotUnit
            }
        ]
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
