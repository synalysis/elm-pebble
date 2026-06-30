module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.System as System
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { battery : Maybe Int
    , connected : Maybe Bool
    , batteryEvents : Int
    , connectionEvents : Int
    }


type Msg
    = SelectPressed
    | GotBattery Int
    | GotConnection Bool
    | BatteryChanged Int
    | ConnectionChanged Bool


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { battery = Nothing
      , connected = Nothing
      , batteryEvents = 0
      , connectionEvents = 0
      }
    , Cmd.batch
        [ System.batteryLevel GotBattery
        , System.connectionStatus GotConnection
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            ( model
            , Cmd.batch
                [ System.batteryLevel GotBattery
                , System.connectionStatus GotConnection
                ]
            )

        GotBattery level ->
            ( { model | battery = Just level }, Cmd.none )

        GotConnection isConnected ->
            ( { model | connected = Just isConnected }, Cmd.none )

        BatteryChanged level ->
            ( { model | battery = Just level, batteryEvents = model.batteryEvents + 1 }, Cmd.none )

        ConnectionChanged isConnected ->
            ( { model | connected = Just isConnected, connectionEvents = model.connectionEvents + 1 }
            , Cmd.none
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Select SelectPressed
        , System.onBatteryChange BatteryChanged
        , System.onConnectionChange ConnectionChanged
        ]


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "System"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } ("Batt: " ++ maybePercent model.battery)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } ("Phone: " ++ maybeBool model.connected)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } ("Batt Δ: " ++ String.fromInt model.batteryEvents)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 104, w = 136, h = 18 } ("Conn Δ: " ++ String.fromInt model.connectionEvents)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 128, w = 136, h = 18 } "Sel: poll"
        ]


maybePercent : Maybe Int -> String
maybePercent maybeValue =
    case maybeValue of
        Nothing ->
            "--"

        Just value ->
            String.fromInt value ++ "%"


maybeBool : Maybe Bool -> String
maybeBool maybeValue =
    case maybeValue of
        Nothing ->
            "--"

        Just True ->
            "yes"

        Just False ->
            "no"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
