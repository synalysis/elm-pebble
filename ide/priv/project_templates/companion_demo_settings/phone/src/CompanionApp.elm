module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion as Companion
import Pebble.Companion.Configuration as Configuration
import Pebble.Companion.Lifecycle as Lifecycle
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { ready : Bool
    , visible : Bool
    , configClosed : Bool
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | LifecycleChanged Lifecycle.Event
    | ConfigurationClosed (Maybe String)


init : Platform.Flags -> ( Model, Cmd Msg )
init _ =
    ( { ready = False, visible = True, configClosed = False }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok OpenSettings) ->
            ( model, Configuration.open "https://example.com/settings" )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        LifecycleChanged event ->
            case event of
                Lifecycle.Ready ->
                    ( { model | ready = True }
                    , Phone.sendPhoneToWatch SettingsReady
                    )

                Lifecycle.ShowConfiguration ->
                    ( model, Cmd.none )

                Lifecycle.WebViewClosed _ ->
                    ( { model | configClosed = True }
                    , Phone.sendPhoneToWatch (SettingsClosed True)
                    )

                Lifecycle.VisibilityChanged visible ->
                    ( { model | visible = visible }, Cmd.none )

                Lifecycle.Unknown _ ->
                    ( model, Cmd.none )

        ConfigurationClosed maybeResponse ->
            ( { model | configClosed = maybeResponse /= Nothing }
            , Phone.sendPhoneToWatch (SettingsClosed (maybeResponse /= Nothing))
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Companion.batch
            [ Lifecycle.part LifecycleChanged
            , Configuration.part ConfigurationClosed
            ]
        ]


main : Platform.Program Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
