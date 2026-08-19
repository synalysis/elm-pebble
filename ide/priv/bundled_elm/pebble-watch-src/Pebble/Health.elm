module Pebble.Health exposing
    ( Event(..)
    , Metric(..)
    , accessible
    , hrvPpiMs
    , onEvent
    , setHeartRateSamplePeriod
    , setHrvSamplePeriod
    , sum
    , sumToday
    , supported
    , value
    )

{-| Access Pebble Health data such as step count, active time, distance, sleep,
calories, heart rate, and heart-rate variability.

Check `supported` first on older watches, then request metrics and subscribe to
service events for live updates.

    import Pebble.Health as Health

    type Msg
        = GotSupported Bool
        | GotSteps Int
        | HealthEvent Health.Event

    init _ =
        ( model
        , Cmd.batch
            [ Health.supported GotSupported
            , Health.value Health.StepCount GotSteps
            ]
        )

    subscriptions _ =
        Health.onEvent HealthEvent

Heart-rate variability is collected only while an app holds an HRV sample
period. Use `setHrvSamplePeriod` to start sampling and `hrvPpiMs` to read the
latest peak-to-peak interval. HRV requires firmware 4.32+ on watches whose
sensor supports it.

For a runnable example, use the **watch-demo-health** project template in the IDE.

# Types
@docs Metric, Event

# Commands
@docs supported, value, sumToday, sum, accessible, hrvPpiMs, setHeartRateSamplePeriod, setHrvSamplePeriod

# Subscriptions
@docs onEvent

-}

import Elm.Kernel.PebbleWatch


{-| Request whether the Health API is available on this watch.
-}
supported : (Bool -> msg) -> Cmd msg
supported =
    Elm.Kernel.PebbleWatch.healthSupported


{-| A Pebble health metric.
-}
type Metric
    = StepCount
    | ActiveSeconds
    | WalkedDistanceMeters
    | SleepSeconds
    | RestfulSleepSeconds
    | RestingKCalories
    | ActiveKCalories
    | HeartRateBPM


{-| A Pebble health service event.
-}
type Event
    = SignificantUpdate
    | MovementUpdate
    | SleepUpdate
    | HeartRateUpdate
    | HrvUpdate


{-| Request the current value for a metric.

For example, `value StepCount GotSteps` requests the current step count.
-}
value : Metric -> (Int -> msg) -> Cmd msg
value metric =
    Elm.Kernel.PebbleWatch.healthValue (metricToInt metric)


{-| Request today's total for a metric.
-}
sumToday : Metric -> (Int -> msg) -> Cmd msg
sumToday metric =
    Elm.Kernel.PebbleWatch.healthSumToday (metricToInt metric)


{-| Request the total for a metric between two Unix timestamps in seconds.
-}
sum : Metric -> Int -> Int -> (Int -> msg) -> Cmd msg
sum metric startSeconds endSeconds =
    Elm.Kernel.PebbleWatch.healthSum (metricToInt metric) startSeconds endSeconds


{-| Request whether a metric is available between two Unix timestamps in seconds.
-}
accessible : Metric -> Int -> Int -> (Bool -> msg) -> Cmd msg
accessible metric startSeconds endSeconds =
    Elm.Kernel.PebbleWatch.healthAccessible (metricToInt metric) startSeconds endSeconds


{-| Request the latest heart-rate variability peak-to-peak interval in milliseconds.

Returns `0` when no reading is available yet, or when the watch/firmware does
not support HRV.
-}
hrvPpiMs : (Int -> msg) -> Cmd msg
hrvPpiMs =
    Elm.Kernel.PebbleWatch.healthHrvPpiMs


{-| Request a heart-rate sample period in seconds.

Pass `0` to release the request. Heart-rate and HRV sample periods are
independent and share the app's sensor subscription.
-}
setHeartRateSamplePeriod : Int -> Cmd msg
setHeartRateSamplePeriod =
    Elm.Kernel.PebbleWatch.healthSetHeartRateSamplePeriod


{-| Request an HRV sample period in seconds.

Pass `0` to stop HRV collection. HRV is only sampled while a period is held.
-}
setHrvSamplePeriod : Int -> Cmd msg
setHrvSamplePeriod =
    Elm.Kernel.PebbleWatch.healthSetHrvSamplePeriod


{-| Receive health service events.
-}
onEvent : (Event -> msg) -> Sub msg
onEvent =
    Elm.Kernel.PebbleWatch.onHealthEvent


metricToInt metric =
    case metric of
        StepCount ->
            0

        ActiveSeconds ->
            1

        WalkedDistanceMeters ->
            2

        SleepSeconds ->
            3

        RestfulSleepSeconds ->
            4

        RestingKCalories ->
            5

        ActiveKCalories ->
            6

        HeartRateBPM ->
            7
