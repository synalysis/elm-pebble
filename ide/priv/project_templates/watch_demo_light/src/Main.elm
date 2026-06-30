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
    , backlight : Maybe Light.State
    , lightChanges : Int
    }


type Msg
    = UpPressed
    | SelectPressed
    | DownPressed
    | LightChanged Light.State


modes : List ( String, Cmd Msg )
modes =
    [ ( "Interaction", Light.interaction )
    , ( "Enable", Light.enable )
    , ( "Disable", Light.disable )
    ]


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { modeIndex = 0, applies = 0, backlight = Nothing, lightChanges = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            ( { model | modeIndex = prevIndex model.modeIndex }, Cmd.none )

        DownPressed ->
            ( { model | modeIndex = nextIndex model.modeIndex }, Cmd.none )

        SelectPressed ->
            applyMode { model | applies = model.applies + 1 }

        LightChanged state ->
            ( { model | backlight = Just state, lightChanges = model.lightChanges + 1 }, Cmd.none )


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


lightLabel : Maybe Light.State -> String
lightLabel maybeState =
    case maybeState of
        Nothing ->
            "Light: --"

        Just Light.On ->
            "Light: on"

        Just Light.Off ->
            "Light: off"


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Down DownPressed
        , Light.onChange LightChanged
        ]


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Backlight"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (modeLabel model)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (lightLabel model.backlight)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } (String.fromInt model.lightChanges)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 104, w = 136, h = 18 } "Up/Dn: mode"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 122, w = 136, h = 18 } "Sel: apply"
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
