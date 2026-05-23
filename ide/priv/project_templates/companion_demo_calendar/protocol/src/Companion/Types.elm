module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

{-| Demo protocol for calendar companion APIs.

Shows `Pebble.Companion.Calendar`.
-}


type WatchToPhone
    = RequestCalendar


type PhoneToWatch
    = ProvideNextEvent String Int Int
    | NoUpcomingEvents
