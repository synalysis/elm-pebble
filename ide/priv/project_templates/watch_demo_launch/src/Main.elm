module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button exposing (Button(..))
import Pebble.Platform as Platform exposing (LaunchReason(..), QuickLaunchAction(..))
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { launchReason : LaunchReason
    , watchModel : String
    , launchButton : Maybe Button
    , quickLaunchAction : QuickLaunchAction
    }


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { launchReason = context.reason
      , watchModel = context.watchModel
      , launchButton = context.launchButton
      , quickLaunchAction = context.quickLaunchAction
      }
    , Cmd.none
    )


type Msg
    = NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 18 } "Launch context"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 28, w = 136, h = 18 } (launchReasonLabel model.launchReason)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 48, w = 136, h = 18 } model.watchModel
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 68, w = 136, h = 18 } (buttonLabel model.launchButton)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 88, w = 136, h = 18 } (quickLaunchLabel model.quickLaunchAction)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 112, w = 136, h = 18 } "Read LaunchContext in init"
        ]


launchReasonLabel : LaunchReason -> String
launchReasonLabel reason =
    case reason of
        LaunchSystem ->
            "Reason: system"

        LaunchUser ->
            "Reason: user"

        LaunchPhone ->
            "Reason: phone"

        LaunchWakeup ->
            "Reason: wakeup"

        LaunchWorker ->
            "Reason: worker"

        LaunchQuickLaunch ->
            "Reason: quick launch"

        LaunchTimelineAction ->
            "Reason: timeline"

        LaunchSmartstrap ->
            "Reason: smartstrap"

        LaunchUnknown ->
            "Reason: unknown"


buttonLabel : Maybe Button -> String
buttonLabel maybeButton =
    case maybeButton of
        Nothing ->
            "Button: none"

        Just Back ->
            "Button: back"

        Just Up ->
            "Button: up"

        Just Select ->
            "Button: select"

        Just Down ->
            "Button: down"


quickLaunchLabel : QuickLaunchAction -> String
quickLaunchLabel action =
    case action of
        QuickLaunchNone ->
            "Quick: none"

        QuickLaunchHold ->
            "Quick: hold"

        QuickLaunchTap ->
            "Quick: tap"

        QuickLaunchCombo ->
            "Quick: combo"

        QuickLaunchUnknown ->
            "Quick: unknown"


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
