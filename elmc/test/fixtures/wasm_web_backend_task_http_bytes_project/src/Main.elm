module Main exposing (main)

import BackendTask.Http
import Browser
import Bytes.Decode as Decode
import Bytes.Encode as Encode
import Html exposing (Html, text)
import Task


type alias Model =
    { value : Maybe Int
    , posted : Bool
    }


type Msg
    = GotGet (Result String Int)
    | GotPost (Result String ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotGet (Ok value) ->
            ( { model | value = Just value }, Cmd.none )

        GotGet (Err _) ->
            ( model, Cmd.none )

        GotPost (Ok _) ->
            ( { model | posted = True }, Cmd.none )

        GotPost (Err _) ->
            ( model, Cmd.none )


view : Model -> Html Msg
view model =
    case ( model.value, model.posted ) of
        ( Just value, True ) ->
            text (String.fromInt value ++ ":posted")

        ( Just value, False ) ->
            text (String.fromInt value)

        _ ->
            text "pending"


init : () -> ( Model, Cmd Msg )
init _ =
    ( { value = Nothing, posted = False }
    , Cmd.batch
        [ Task.attempt GotGet <|
            BackendTask.Http.get
                "https://example.com/data.bin"
                (BackendTask.Http.expectBytes Decode.unsignedInt8)
        , Task.attempt GotPost <|
            BackendTask.Http.post
                "https://example.com/upload.bin"
                (BackendTask.Http.bytesBody "application/octet-stream" <|
                    Encode.sequence
                        [ Encode.unsignedInt8 7
                        , Encode.unsignedInt8 8
                        ]
                )
                (BackendTask.Http.expectWhatever ())
        ]
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
