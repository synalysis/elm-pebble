module Main exposing (main)

import Browser
import File exposing (File)
import File.Select as Select
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (id)
import Html.Events exposing (onClick)
import Http


type alias Model =
    { body : String
    , part : String
    }


type Msg
    = Pick
    | GotFile File
    | GotBody (Result Http.Error ())
    | GotPart (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Pick ->
            ( model, Select.file [ "text/plain" ] GotFile )

        GotFile file ->
            ( model
            , Cmd.batch
                [ Http.post
                    { url = "https://example.com/file"
                    , body = Http.fileBody file
                    , expect = Http.expectWhatever GotBody
                    }
                , Http.post
                    { url = "https://example.com/part"
                    , body = Http.multipartBody [ Http.filePart "doc" file ]
                    , expect = Http.expectWhatever GotPart
                    }
                ]
            )

        GotBody (Ok ()) ->
            ( { model | body = "ok" }, Cmd.none )

        GotBody (Err _) ->
            ( { model | body = "err" }, Cmd.none )

        GotPart (Ok ()) ->
            ( { model | part = "ok" }, Cmd.none )

        GotPart (Err _) ->
            ( { model | part = "err" }, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ button [ id "pick", onClick Pick ] [ text "pick" ]
        , div [ id "out" ] [ text (model.body ++ "|" ++ model.part) ]
        ]


init : () -> ( Model, Cmd Msg )
init _ =
    ( { body = "wait", part = "wait" }, Cmd.none )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
