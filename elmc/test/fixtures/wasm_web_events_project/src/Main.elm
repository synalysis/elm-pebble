module Main exposing (main)

import Browser
import Html exposing (Html, button, div, form, input, text)
import Html.Attributes exposing (type_)
import Html.Events exposing (onCheck, onClick, onInput, onSubmit)


type alias Model =
    String


type Msg
    = Clicked
    | Typed String
    | Submitted
    | Checked Bool


init : Model
init =
    "hello"


update : Msg -> Model -> Model
update msg _ =
    case msg of
        Clicked ->
            "clicked"

        Typed value ->
            value

        Submitted ->
            "submitted"

        Checked _ ->
            "checked"


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Clicked ] [ text model ]
        , input [ onInput Typed ] []
        , input [ type_ "checkbox", onCheck Checked ] []
        , form [ onSubmit Submitted ] [ button [] [ text "go" ] ]
        ]


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
