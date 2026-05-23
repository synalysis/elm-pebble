module CompanionApp exposing (main)

import Companion.Types exposing (ConfigurationOutcome(..), PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion.Configuration as Configuration
import Pebble.Companion.Lifecycle as Lifecycle
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { ready : Bool
    , visible : Bool
    , configOutcome : Maybe ConfigurationOutcome
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | LifecycleChanged Lifecycle.Event
    | ConfigurationClosed (Maybe String)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { ready = False, visible = True, configOutcome = Nothing }
    , Cmd.batch [ Lifecycle.setup, Configuration.setup ]
    )


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
                    ( { model | configOutcome = Just Dismissed }
                    , Phone.sendPhoneToWatch (SettingsClosed Dismissed)
                    )

                Lifecycle.VisibilityChanged visible ->
                    ( { model | visible = visible }, Cmd.none )

                Lifecycle.Unknown _ ->
                    ( model, Cmd.none )

        ConfigurationClosed maybeResponse ->
            let
                outcome =
                    if maybeResponse == Nothing then
                        Dismissed

                    else
                        Saved
            in
            ( { model | configOutcome = Just outcome }
            , Phone.sendPhoneToWatch (SettingsClosed outcome)
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Lifecycle.onLifecycle LifecycleChanged
        , Configuration.onClosed ConfigurationClosed
        ]


main : Platform.Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
