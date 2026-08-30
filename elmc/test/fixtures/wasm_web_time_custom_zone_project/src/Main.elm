module Main exposing (main)

import Html exposing (Html, text)
import Time


epoch : Time.Posix
epoch =
    Time.millisToPosix 0


clock : Time.Zone -> String
clock zone =
    String.fromInt (Time.toHour zone epoch) ++ ":" ++ String.fromInt (Time.toMinute zone epoch)


main : Html String
main =
    text
        (String.join "|"
            [ "utc:" ++ clock Time.utc
            , "plus60:" ++ clock (Time.customZone 60 [])
            , "era:" ++ clock (Time.customZone 0 [ { start = -1, offset = 120 } ])
            , "skip:" ++ clock (Time.customZone 30 [ { start = 1, offset = 120 } ])
            ]
        )
