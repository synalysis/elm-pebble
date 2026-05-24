module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Light as Light
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { modeIndex : Int
    , applies : Int
    }


type Msg
    = UpPressed
    | SelectPressed
    | DownPressed


modes : List ( String, Cmd Msg )
modes =
    [ ( "Interaction", Light.interaction )
    , ( "Enable", Light.enable )
    , ( "Disable", Light.disable )
    ]


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { modeIndex = 0, applies = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            ( { model | modeIndex = prevIndex model.modeIndex }, Cmd.none )

        DownPressed ->
            ( { model | modeIndex = nextIndex model.modeIndex }, Cmd.none )

        SelectPressed ->
            applyMode { model | applies = model.applies + 1 }


applyMode : Model -> ( Model, Cmd Msg )
applyMode model =
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
        |> Maybe.withDefault ( "Interaction", Light.interaction )


prevIndex : Int -> Int
prevIndex index =
    modBy (List.length modes) (index - 1 + List.length modes)


nextIndex : Int -> Int
nextIndex index =
    modBy (List.length modes) (index + 1)


modeLabel : Model -> String
modeLabel model =
    Tuple.first (currentMode model.modeIndex)


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "Light demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 36, w = 136, h = 20 } (modeLabel model)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 64, w = 136, h = 20 } (String.fromInt model.applies)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 92, w = 136, h = 40 } "Up/Down: mode Select: apply"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
