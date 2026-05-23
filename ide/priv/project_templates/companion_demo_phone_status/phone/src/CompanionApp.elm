module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion as Companion
import Pebble.Companion.Battery as Battery
import Pebble.Companion.Connectivity as Connectivity
import Pebble.Companion.Locale as Locale
import Pebble.Companion.Notifications as Notifications
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { batteryPercent : Int
    , charging : Bool
    , locale : String
    , online : Bool
    , notificationsEnabled : Bool
    , quietHours : Bool
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotBattery (Result String Battery.BatteryInfo)
    | GotLocale (Result String Locale.LocaleInfo)
    | GotConnectivity Connectivity.Connectivity
    | GotNotifications (Result String Notifications.NotificationStatus)


init : Platform.Flags -> ( Model, Cmd Msg )
init _ =
    ( emptyModel, refreshAll )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestPhoneStatus) ->
            ( model, refreshAll )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotBattery (Ok info) ->
            ( { model | batteryPercent = info.percent, charging = info.charging }
            , Phone.sendPhoneToWatch (ProvideBattery info.percent info.charging)
            )

        GotBattery (Err _) ->
            ( model, Cmd.none )

        GotLocale (Ok info) ->
            ( { model | locale = info.locale }
            , Phone.sendPhoneToWatch (ProvideLocale info.locale)
            )

        GotLocale (Err _) ->
            ( model, Cmd.none )

        GotConnectivity connectivity ->
            let
                online =
                    connectivity == Connectivity.Online
            in
            ( { model | online = online }
            , Phone.sendPhoneToWatch (ProvideConnectivity online)
            )

        GotNotifications (Ok info) ->
            ( { model | notificationsEnabled = info.notificationsEnabled, quietHours = info.quietHours }
            , Phone.sendPhoneToWatch (ProvideNotifications info.notificationsEnabled info.quietHours)
            )

        GotNotifications (Err _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Companion.batch
            [ Battery.part GotBattery
            , Locale.part GotLocale
            , Connectivity.part GotConnectivity
            , Notifications.part GotNotifications
            ]
        ]


main : Platform.Program Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


emptyModel : Model
emptyModel =
    { batteryPercent = 0
    , charging = False
    , locale = "--"
    , online = False
    , notificationsEnabled = False
    , quietHours = False
    }


refreshAll : Cmd Msg
refreshAll =
    Cmd.batch
        [ Battery.current GotBattery
        , Locale.current GotLocale
        , Connectivity.current GotConnectivity
        , Notifications.current GotNotifications
        ]
