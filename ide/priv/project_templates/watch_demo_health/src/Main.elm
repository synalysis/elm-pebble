module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Health as Health
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { supported : Maybe Bool
    , stepsNow : Maybe Int
    , stepsToday : Maybe Int
    , heartRate : Maybe Int
    , hrvPpiMs : Maybe Int
    , lastEvent : String
    , refreshes : Int
    }


type Msg
    = SelectPressed
    | GotSupported Bool
    | GotStepsNow Int
    | GotStepsToday Int
    | GotHeartRate Int
    | GotHrv Int
    | HealthEvent Health.Event


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { supported = Nothing
      , stepsNow = Nothing
      , stepsToday = Nothing
      , heartRate = Nothing
      , hrvPpiMs = Nothing
      , lastEvent = "Waiting"
      , refreshes = 0
      }
    , Health.supported GotSupported
    )


requestHealth : Cmd Msg
requestHealth =
    Cmd.batch
        [ Health.setHeartRateSamplePeriod 10
        , Health.setHrvSamplePeriod 10
        , Health.value Health.StepCount GotStepsNow
        , Health.sumToday Health.StepCount GotStepsToday
        , Health.value Health.HeartRateBPM GotHeartRate
        , Health.hrvPpiMs GotHrv
        ]


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            case model.supported of
                Just True ->
                    ( { model | refreshes = model.refreshes + 1 }, requestHealth )

                _ ->
                    ( { model | refreshes = model.refreshes + 1 }, Health.supported GotSupported )

        GotSupported True ->
            ( { model | supported = Just True }, requestHealth )

        GotSupported False ->
            ( { model | supported = Just False }, Cmd.none )

        GotStepsNow value ->
            ( { model | stepsNow = Just value }, Cmd.none )

        GotStepsToday value ->
            ( { model | stepsToday = Just value }, Cmd.none )

        GotHeartRate value ->
            ( { model | heartRate = Just value }, Cmd.none )

        GotHrv value ->
            ( { model | hrvPpiMs = Just value }, Cmd.none )

        HealthEvent event ->
            ( { model | lastEvent = healthEventLabel event }
            , healthEventCmd event
            )


healthEventCmd : Health.Event -> Cmd Msg
healthEventCmd event =
    case event of
        Health.HeartRateUpdate ->
            Health.value Health.HeartRateBPM GotHeartRate

        Health.HrvUpdate ->
            Health.hrvPpiMs GotHrv

        Health.MovementUpdate ->
            requestSteps

        Health.SignificantUpdate ->
            requestSteps

        Health.SleepUpdate ->
            Cmd.none


requestSteps : Cmd Msg
requestSteps =
    Cmd.batch
        [ Health.value Health.StepCount GotStepsNow
        , Health.sumToday Health.StepCount GotStepsToday
        ]


healthEventLabel : Health.Event -> String
healthEventLabel event =
    case event of
        Health.SignificantUpdate ->
            "Significant"

        Health.MovementUpdate ->
            "Movement"

        Health.SleepUpdate ->
            "Sleep"

        Health.HeartRateUpdate ->
            "Heart rate"

        Health.HrvUpdate ->
            "HRV"


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.supported of
        Just False ->
            Events.batch [ Button.onPress Button.Select SelectPressed ]

        _ ->
            Events.batch
                [ Health.onEvent HealthEvent
                , Button.onPress Button.Select SelectPressed
                ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        (Ui.clear Color.white
            :: Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 18 } "Health demo"
            :: bodyLines model
        )


bodyLines : Model -> List Ui.RenderOp
bodyLines model =
    case model.supported of
        Just False ->
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 40, w = 136, h = 18 } "Health API not supported on this watch"
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 120, w = 136, h = 18 } "Select: recheck"
            ]

        _ ->
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 28, w = 136, h = 18 } ("Now: " ++ intLabel model.stepsNow)
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 48, w = 136, h = 18 } ("Today: " ++ intLabel model.stepsToday)
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 68, w = 136, h = 18 } ("HR: " ++ intLabel model.heartRate)
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 88, w = 136, h = 18 } ("HRV: " ++ intLabel model.hrvPpiMs)
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 108, w = 136, h = 18 } model.lastEvent
            , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 128, w = 136, h = 18 } "Select: refresh"
            ]


intLabel : Maybe Int -> String
intLabel maybeValue =
    case maybeValue of
        Nothing ->
            "--"

        Just value ->
            String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
