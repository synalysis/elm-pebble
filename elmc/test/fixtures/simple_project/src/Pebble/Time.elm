module Pebble.Time exposing (clockStyle24h, currentTimeString, timezone, timezoneIsSet)

import Elm.Kernel.PebbleWatch


currentTimeString : (String -> msg) -> Cmd msg
currentTimeString =
    Elm.Kernel.PebbleWatch.getCurrentTimeString


clockStyle24h : (Bool -> msg) -> Cmd msg
clockStyle24h =
    Elm.Kernel.PebbleWatch.getClockStyle24h


timezoneIsSet : (Bool -> msg) -> Cmd msg
timezoneIsSet =
    Elm.Kernel.PebbleWatch.getTimezoneIsSet


timezone : (String -> msg) -> Cmd msg
timezone =
    Elm.Kernel.PebbleWatch.getTimezone
