module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (id)
import Html.Events exposing (custom, preventDefaultOn, stopPropagationOn)
import Json.Decode as Decode


type alias Model =
    String


type Msg
    = Prevented
    | Stopped
    | CustomClicked


update : Msg -> Model -> Model
update msg model =
    case msg of
        Prevented ->
            model ++ "P"

        Stopped ->
            model ++ "S"

        CustomClicked ->
            model ++ "C"


view : Model -> Html Msg
view model =
    div []
        [ div [ id "out" ] [ text model ]
        , button
            [ id "prevent"
            , preventDefaultOn "click" (Decode.succeed ( Prevented, True ))
            ]
            [ text "prevent" ]
        , button
            [ id "stop"
            , stopPropagationOn "click" (Decode.succeed ( Stopped, True ))
            ]
            [ text "stop" ]
        , button
            [ id "custom"
            , custom "click"
                (Decode.succeed
                    { message = CustomClicked
                    , stopPropagation = True
                    , preventDefault = True
                    }
                )
            ]
            [ text "custom" ]
        ]


main : Program () Model Msg
main =
    Browser.sandbox
        { init = ""
        , update = update
        , view = view
        }
