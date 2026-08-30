module Main exposing (main)

import Html exposing (Html, text)
import Time


epoch : Time.Posix
epoch =
    Time.millisToPosix 0


monthLabel : Time.Month -> String
monthLabel month =
    case month of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"


weekdayLabel : Time.Weekday -> String
weekdayLabel day =
    case day of
        Time.Mon ->
            "Mon"

        Time.Tue ->
            "Tue"

        Time.Wed ->
            "Wed"

        Time.Thu ->
            "Thu"

        Time.Fri ->
            "Fri"

        Time.Sat ->
            "Sat"

        Time.Sun ->
            "Sun"


main : Html String
main =
    let
        month =
            Time.toMonth Time.utc epoch

        weekday =
            Time.toWeekday Time.utc epoch
    in
    text
        (String.join " "
            [ monthLabel month
            , weekdayLabel weekday
            , String.fromInt (Time.toYear Time.utc epoch)
            , String.fromInt (Time.toDay Time.utc epoch)
            , String.fromInt (Time.toHour Time.utc epoch)
                ++ ":"
                ++ String.fromInt (Time.toMinute Time.utc epoch)
                ++ ":"
                ++ String.fromInt (Time.toSecond Time.utc epoch)
                ++ "."
                ++ String.fromInt (Time.toMillis Time.utc epoch)
            , if month == Time.Jan then
                "eq"

              else
                "neq"
            , String.fromInt (Time.posixToMillis epoch)
            ]
        )
