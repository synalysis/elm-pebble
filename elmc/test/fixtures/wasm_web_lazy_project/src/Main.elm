module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (id)
import Html.Events exposing (onClick)
import Html.Lazy
import Task


type alias Model =
    { n : Int
    , dummy : Int
    }


type Msg
    = Tick
    | Noop


init : () -> ( Model, Cmd Msg )
init _ =
    ( { n = 0, dummy = 0 }
    , Task.perform (\_ -> Noop) (Task.succeed ())
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick ->
            ( { model | n = model.n + 1 }, Cmd.none )

        Noop ->
            ( { model | dummy = model.dummy + 1 }, Cmd.none )


viewCount : Int -> Html Msg
viewCount n =
    text (Debug.log "lazy" (String.fromInt n))


viewPair : Int -> Int -> Html Msg
viewPair n dummy =
    text (Debug.log "lazy2" (String.fromInt n ++ "," ++ String.fromInt dummy))


view : Model -> Html Msg
view model =
    div []
        [ button [ id "tick", onClick Tick ] [ text "tick" ]
        , div [ id "state" ]
            [ text (String.fromInt model.n ++ ":" ++ String.fromInt model.dummy) ]
        , div [ id "out" ] [ Html.Lazy.lazy viewCount model.n ]
        , div [ id "pair" ] [ Html.Lazy.lazy2 viewPair model.n model.dummy ]
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
