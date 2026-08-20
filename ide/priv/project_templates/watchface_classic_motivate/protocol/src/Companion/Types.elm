module Companion.Types exposing (PhoneToWatch(..), ThemeColor(..), WatchToPhone(..))

{-| Shared messages for the Classic Motivate watchface.
-}


type WatchToPhone
    = RequestSettings


type ThemeColor
    = WatchBody
    | Cream
    | White
    | Black
    | Brass
    | Navy
    | Slate
    | Burgundy
    | Magenta


type PhoneToWatch
    = SetMotivationalText String
    | SetWatchDisplaySeconds Int
    | SetQuoteDisplaySeconds Int
    | SetWatchBackground ThemeColor
    | SetWatchForeground ThemeColor
    | SetQuoteBackground ThemeColor
    | SetQuoteTextColor ThemeColor
