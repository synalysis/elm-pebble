module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Dictation as Dictation
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { hasMicrophone : Bool
    , status : Maybe Dictation.Status
    , result : Result Dictation.Error String
    }


type Msg
    = SelectPressed
    | DownPressed
    | DictationStatusChanged Dictation.Status
    | DictationFinished (Result Dictation.Error String)


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { hasMicrophone = context.hasMicrophone
      , status =
            if context.hasMicrophone then
                Nothing

            else
                Just Dictation.Finished
      , result =
            if context.hasMicrophone then
                Ok ""

            else
                Err Dictation.NoMicrophone
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            if model.hasMicrophone then
                ( { model | status = Just Dictation.Starting, result = Ok "" }, Dictation.start )

            else
                ( model, Cmd.none )

        DownPressed ->
            if model.hasMicrophone then
                ( model, Dictation.stop )

            else
                ( model, Cmd.none )

        DictationStatusChanged status ->
            ( { model | status = Just status }, Cmd.none )

        DictationFinished result ->
            ( { model | status = Just Dictation.Finished, result = result }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.hasMicrophone then
        Events.batch
            [ Dictation.onStatus DictationStatusChanged
            , Dictation.onResult DictationFinished
            , Button.onPress Button.Select SelectPressed
            , Button.onPress Button.Down DownPressed
            ]

    else
        Events.batch []


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Dictation"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (statusLabel model.status model.hasMicrophone)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (truncateText (resultLabel model.result) 16)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 92, w = 136, h = 18 } "Sel: start"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 110, w = 136, h = 18 } "Down: stop"
        ]


statusLabel : Maybe Dictation.Status -> Bool -> String
statusLabel maybeStatus hasMicrophone =
    if not hasMicrophone then
        "No mic"

    else
        case maybeStatus of
            Nothing ->
                "Ready"

            Just Dictation.Starting ->
                "Starting"

            Just Dictation.Recognizing ->
                "Listening"

            Just Dictation.Finished ->
                "Finished"


truncateText : String -> Int -> String
truncateText text_ maxLen =
    if String.length text_ <= maxLen then
        text_

    else
        String.left maxLen text_


resultLabel : Result Dictation.Error String -> String
resultLabel result =
    case result of
        Ok transcript ->
            transcript

        Err Dictation.NoMicrophone ->
            "No mic"

        Err Dictation.PhoneDisconnected ->
            "No phone"

        Err Dictation.Cancelled ->
            "Cancelled"

        Err (Dictation.Failed detail) ->
            detail


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
