module Main exposing (main)

import Browser
import Bytes exposing (Bytes)
import Bytes.Decode as Decode
import File exposing (File)
import File.Select as Select
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (id)
import Html.Events exposing (onClick)
import Task


type alias Model =
    { name : String
    , text : String
    , url : String
    , firstByte : String
    }


type Msg
    = Pick
    | GotFile File
    | GotText String
    | GotDataUrl String
    | GotBytes Bytes


init : () -> ( Model, Cmd Msg )
init _ =
    ( { name = "", text = "", url = "", firstByte = "" }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Pick ->
            ( model, Select.file [ "text/plain" ] GotFile )

        GotFile file ->
            ( { model | name = File.name file }
            , Cmd.batch
                [ Task.perform GotText (File.toString file)
                , Task.perform GotDataUrl (File.toUrl file)
                , Task.perform GotBytes (File.toBytes file)
                ]
            )

        GotText text ->
            ( { model | text = text }, Cmd.none )

        GotDataUrl url ->
            ( { model | url = url }, Cmd.none )

        GotBytes bytes ->
            ( { model | firstByte = firstByteLabel bytes }, Cmd.none )


firstByteLabel : Bytes -> String
firstByteLabel bytes =
    case Decode.decode Decode.unsignedInt8 bytes of
        Just n ->
            String.fromInt n

        Nothing ->
            "none"


view : Model -> Html Msg
view model =
    div []
        [ button [ id "pick", onClick Pick ] [ text "pick" ]
        , div [ id "out" ]
            [ text
                (model.name
                    ++ "|"
                    ++ model.text
                    ++ "|"
                    ++ model.url
                    ++ "|"
                    ++ model.firstByte
                )
            ]
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
