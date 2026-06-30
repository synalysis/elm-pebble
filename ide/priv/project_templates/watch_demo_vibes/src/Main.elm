module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.Vibes as Vibes


type alias Model =
    { patternIndex : Int
    , presses : Int
    }


type Msg
    = UpPressed
    | SelectPressed
    | DownPressed


patterns : List ( String, List Int )
patterns =
    [ ( "Short-long", [ 100, 50, 300 ] )
    , ( "SOS", [ 100, 100, 100, 100, 100, 300, 300, 300, 100, 100, 100 ] )
    , ( "Heartbeat", [ 80, 80, 80, 200, 80, 80, 80, 400 ] )
    ]


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { patternIndex = 0, presses = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            playPattern { model | patternIndex = prevIndex model.patternIndex }

        SelectPressed ->
            playPattern { model | presses = model.presses + 1 }

        DownPressed ->
            playPattern { model | patternIndex = nextIndex model.patternIndex }


playPattern : Model -> ( Model, Cmd Msg )
playPattern model =
    case currentPattern model.patternIndex of
        ( _, segments ) ->
            ( model, Vibes.pattern segments )


currentPattern : Int -> ( String, List Int )
currentPattern index =
    let
        count =
            List.length patterns

        normalized =
            modBy count (index + count)
    in
    patterns
        |> List.drop normalized
        |> List.head
        |> Maybe.withDefault ( "Pulse", [ 200 ] )


prevIndex : Int -> Int
prevIndex index =
    modBy (List.length patterns) (index - 1 + List.length patterns)


nextIndex : Int -> Int
nextIndex index =
    modBy (List.length patterns) (index + 1)


patternLabel : Model -> String
patternLabel model =
    Tuple.first (currentPattern model.patternIndex)


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Vibes"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (patternLabel model)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (String.fromInt model.presses)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } "Up/Dn: pattern"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 98, w = 136, h = 18 } "Sel: play"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
