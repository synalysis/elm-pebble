module Pebble.Cmd exposing
    ( CurrentDateTime
    , DayOfWeek(..)
    , companionSend
    , getCurrentDateTime
    , none
    , timerAfter
    )

import Elm.Kernel.PebbleWatch

none : Cmd msg
none =
    Elm.Kernel.PebbleWatch.none


type DayOfWeek
    = Monday
    | Tuesday
    | Wednesday
    | Thursday
    | Friday
    | Saturday
    | Sunday


type alias CurrentDateTime =
    { year : Int
    , month : Int
    , day : Int
    , dayOfWeek : DayOfWeek
    , hour : Int
    , minute : Int
    , second : Int
    , utcOffsetMinutes : Int
    }


timerAfter : Int -> Cmd msg
timerAfter =
    Elm.Kernel.PebbleWatch.timerAfter


companionSend : Int -> Int -> Cmd msg
companionSend =
    Elm.Kernel.PebbleWatch.companionSend


getCurrentDateTime : (CurrentDateTime -> msg) -> Cmd msg
getCurrentDateTime =
    Elm.Kernel.PebbleWatch.getCurrentDateTime
