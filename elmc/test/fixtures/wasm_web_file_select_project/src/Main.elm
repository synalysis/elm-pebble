module Main exposing (main)

import Browser
import File exposing (File)
import File.Download as Download
import File.Select as Select
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (id)
import Html.Events exposing (onClick)


type alias Model =
    String


type Msg
    = Pick
    | Picks
    | Url
    | GotFile File
    | GotFiles File (List File)


init : () -> ( Model, Cmd Msg )
init _ =
    ( "", Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Pick ->
            ( model, Select.file [ "text/plain" ] GotFile )

        Picks ->
            ( model, Select.files [ "text/plain" ] GotFiles )

        Url ->
            ( model, Download.url "https://example.com/a.png" )

        GotFile file ->
            ( File.name file, Cmd.none )

        GotFiles first rest ->
            ( File.name first ++ ":" ++ String.join "," (List.map File.name rest), Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ button [ id "pick", onClick Pick ] [ text "pick" ]
        , button [ id "picks", onClick Picks ] [ text "picks" ]
        , button [ id "url", onClick Url ] [ text "url" ]
        , div [ id "out" ] [ text model ]
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
