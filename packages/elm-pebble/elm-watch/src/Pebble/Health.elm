module Pebble.Health exposing
    ( Event(..)
    , Metric(..)
    , accessible
    , onEvent
    , sum
    , sumToday
    , value
    )

{-| Access Pebble Health data such as step count, active time, distance, sleep,
calories, and heart rate.

# Types
@docs Metric, Event

# Commands
@docs value, sumToday, sum, accessible

# Subscriptions
@docs onEvent

-}

import Elm.Kernel.PebbleWatch


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
