module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.WatchInfo as WatchInfo


type alias Model =
    { model : Maybe WatchInfo.WatchModel
    , color : Maybe WatchInfo.WatchColor
    , firmware : Maybe WatchInfo.FirmwareVersion
    , refreshes : Int
    }


type Msg
    = SelectPressed
    | GotModel WatchInfo.WatchModel
    | GotColor WatchInfo.WatchColor
    | GotFirmware WatchInfo.FirmwareVersion


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { model = Nothing, color = Nothing, firmware = Nothing, refreshes = 0 }, requestInfo )


requestInfo : Cmd Msg
requestInfo =
    Cmd.batch
        [ WatchInfo.getModel GotModel
        , WatchInfo.getColor GotColor
        , WatchInfo.getFirmwareVersion GotFirmware
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( { model | refreshes = model.refreshes + 1 }, requestInfo )

        GotModel value ->
            ( { model | model = Just value }, Cmd.none )

        GotColor value ->
            ( { model | color = Just value }, Cmd.none )

        GotFirmware value ->
            ( { model | firmware = Just value }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch [ Button.onPress Button.Select SelectPressed ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 20 } "WatchInfo demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 136, h = 20 } (maybeLabel model.model watchModelLabel)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 52, w = 136, h = 20 } (maybeLabel model.color watchColorLabel)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 72, w = 136, h = 20 } (maybeLabel model.firmware firmwareLabel)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 96, w = 136, h = 20 } (String.fromInt model.refreshes)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 120, w = 136, h = 20 } "Select: refresh"
        ]


maybeLabel : Maybe a -> (a -> String) -> String
maybeLabel maybeValue toLabel =
    case maybeValue of
        Nothing ->
            "--"

        Just value ->
            toLabel value


watchModelLabel : WatchInfo.WatchModel -> String
watchModelLabel watchModel =
    case watchModel of
        WatchInfo.PebbleOriginal ->
            "Original"

        WatchInfo.PebbleSteel ->
            "Steel"

        WatchInfo.PebbleTime ->
            "Time"

        WatchInfo.PebbleTimeSteel ->
            "Time Steel"

        WatchInfo.PebbleTimeRound14 ->
            "Round 14"

        WatchInfo.PebbleTimeRound20 ->
            "Round 20"

        WatchInfo.Pebble2Hr ->
            "Pebble 2 HR"

        WatchInfo.Pebble2Se ->
            "Pebble 2 SE"

        WatchInfo.PebbleTime2 ->
            "Time 2"

        WatchInfo.UnknownModel ->
            "Unknown"

        _ ->
            "Core device"


watchColorLabel : WatchInfo.WatchColor -> String
watchColorLabel watchColor =
    case watchColor of
        WatchInfo.Black ->
            "Black"

        WatchInfo.White ->
            "White"

        WatchInfo.Red ->
            "Red"

        WatchInfo.Blue ->
            "Blue"

        WatchInfo.Green ->
            "Green"

        WatchInfo.StainlessSteel ->
            "Steel"

        WatchInfo.TimeBlack ->
            "Time black"

        WatchInfo.TimeWhite ->
            "Time white"

        WatchInfo.UnknownColor ->
            "Unknown"

        _ ->
            "Color variant"


firmwareLabel : WatchInfo.FirmwareVersion -> String
firmwareLabel version =
    String.fromInt version.major
        ++ "."
        ++ String.fromInt version.minor
        ++ "."
        ++ String.fromInt version.patch


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
