module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http


type alias Model =
    { progressCount : Int }


type Msg
    = Got (Result Http.Error String)
    | Progress Http.Progress


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Got _ ->
            ( model, Cmd.none )

        Progress progress ->
            case progress of
                Http.Sending _ ->
                    ( { model | progressCount = model.progressCount + 1 }, Cmd.none )

                Http.Receiving _ ->
                    ( { model | progressCount = model.progressCount + 1 }, Cmd.none )


view : Model -> Html Msg
view model =
    text (String.fromInt model.progressCount)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { progressCount = 0 }
    , Http.request
        { method = "GET"
        , headers = []
        , url = "https://example.com/data"
        , body = Http.emptyBody
        , expect = Http.expectString Got
        , timeout = Nothing
        , tracker = Just "download"
        }
    )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Http.track "download" Progress


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
