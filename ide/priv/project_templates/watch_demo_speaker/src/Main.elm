module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Speaker as Speaker
import Pebble.Speaker.Resources as SpeakerResources exposing (Sample(..))
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { modeIndex : Int
    , plays : Int
    , lastFinish : String
    }


type Msg
    = UpPressed
    | SelectPressed
    | DownPressed
    | SpeakerFinished Speaker.FinishReason


modes : List ( String, Cmd Msg )
modes =
    [ ( "Tone 440Hz", Speaker.playTone 440 250 80 Speaker.Sine )
    , ( "Note scale", Speaker.playNotes demoNotes 80 )
    , ( trackModeLabel, Speaker.playTracks demoTracks 80 )
    ]


demoNotes : List Speaker.Note
demoNotes =
    [ note 60 140
    , note 64 140
    , note 67 140
    , note 72 220
    ]


demoTracks : List Speaker.Track
demoTracks =
    case firstSample () of
        Just sample ->
            [ { notes = [ note 60 600 ], sample = Just sample } ]

        Nothing ->
            [ { notes = [ note 48 280 ], sample = Nothing }
            , { notes = [ note 60 140, note 64 140, note 67 220 ], sample = Nothing }
            ]


trackModeLabel : String
trackModeLabel =
    case firstSample () of
        Just _ ->
            "PCM sample"

        Nothing ->
            "Dual track"


firstSample : () -> Maybe Sample
firstSample () =
    SpeakerResources.allSamples
        |> List.filter (\sample -> sample /= NoSample)
        |> List.head


note : Int -> Int -> Speaker.Note
note midiNote durationMs =
    { midiNote = midiNote
    , waveform = Speaker.Sine
    , durationMs = durationMs
    , velocity = 100
    }


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { modeIndex = 0, plays = 0, lastFinish = "Waiting" }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            ( { model | modeIndex = prevIndex model.modeIndex }, Cmd.none )

        DownPressed ->
            ( { model | modeIndex = nextIndex model.modeIndex }, Cmd.none )

        SelectPressed ->
            playMode { model | plays = model.plays + 1 }

        SpeakerFinished reason ->
            ( { model | lastFinish = finishLabel reason }, Cmd.none )


playMode : Model -> ( Model, Cmd Msg )
playMode model =
    case currentMode model.modeIndex of
        ( _, cmd ) ->
            ( model, cmd )


currentMode : Int -> ( String, Cmd Msg )
currentMode index =
    let
        count =
            List.length modes

        normalized =
            modBy count (index + count)
    in
    modes
        |> List.drop normalized
        |> List.head
        |> Maybe.withDefault ( "Tone", Speaker.playTone 440 200 80 Speaker.Sine )


prevIndex : Int -> Int
prevIndex index =
    modBy (List.length modes) (index - 1 + List.length modes)


nextIndex : Int -> Int
nextIndex index =
    modBy (List.length modes) (index + 1)


finishLabel : Speaker.FinishReason -> String
finishLabel reason =
    case reason of
        Speaker.FinishedDone ->
            "Done"

        Speaker.FinishedStopped ->
            "Stopped"

        Speaker.FinishedPreempted ->
            "Preempted"

        Speaker.FinishedError ->
            "Error"

        Speaker.FinishedUnknown ->
            "Unknown"


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Down DownPressed
        , Speaker.onFinished SpeakerFinished
        ]


view : Model -> Ui.UiNode
view model =
    let
        ( label, _ ) =
            currentMode model.modeIndex
    in
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Speaker"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } label
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (String.fromInt model.plays)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } model.lastFinish
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 104, w = 136, h = 18 } "Up/Dn: mode"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 122, w = 136, h = 18 } "Sel: play"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
