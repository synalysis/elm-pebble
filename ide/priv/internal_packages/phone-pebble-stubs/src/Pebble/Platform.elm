module Pebble.Platform exposing
    ( LaunchContext
    , LaunchReason(..)
    , LaunchScreen
    , application
    , launchReasonFromTag
    , launchReasonToInt
    , watchface
    )

import Platform


type LaunchReason
    = LaunchSystem
    | LaunchUser
    | LaunchPhone
    | LaunchWakeup
    | LaunchWorker
    | LaunchQuickLaunch
    | LaunchTimelineAction
    | LaunchSmartstrap
    | LaunchUnknown


type alias LaunchScreen =
    { width : Int
    , height : Int
    , isColor : Bool
    , isRound : Bool
    }


type alias LaunchContext =
    { reason : LaunchReason
    , watchModel : String
    , watchProfileId : String
    , screen : LaunchScreen
    }


watchface :
    { init : LaunchContext -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    }
    -> Program () model msg
watchface config =
    Platform.worker
        { init = \_ -> config.init defaultLaunchContext
        , update = config.update
        , subscriptions = config.subscriptions
        }


application :
    { init : LaunchContext -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    }
    -> Program () model msg
application =
    watchface


launchReasonToInt : LaunchReason -> Int
launchReasonToInt launchReason =
    case launchReason of
        LaunchSystem ->
            0

        LaunchUser ->
            1

        LaunchPhone ->
            2

        LaunchWakeup ->
            3

        LaunchWorker ->
            4

        LaunchQuickLaunch ->
            5

        LaunchTimelineAction ->
            6

        LaunchSmartstrap ->
            7

        LaunchUnknown ->
            -1


launchReasonFromTag : String -> LaunchReason
launchReasonFromTag tag =
    case tag of
        "system" ->
            LaunchSystem

        "user" ->
            LaunchUser

        "phone" ->
            LaunchPhone

        "wakeup" ->
            LaunchWakeup

        "worker" ->
            LaunchWorker

        "quick_launch" ->
            LaunchQuickLaunch

        "timeline_action" ->
            LaunchTimelineAction

        "smartstrap" ->
            LaunchSmartstrap

        _ ->
            LaunchUnknown


defaultLaunchContext : LaunchContext
defaultLaunchContext =
    { reason = LaunchUnknown
    , watchModel = "unknown"
    , watchProfileId = "unknown"
    , screen = { width = 144, height = 168, isColor = True, isRound = False }
    }
