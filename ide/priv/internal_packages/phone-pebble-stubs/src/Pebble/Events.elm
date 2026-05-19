module Pebble.Events exposing
    ( batch
    , onDayChange
    , onHourChange
    , onMinuteChange
    , onMonthChange
    , onSecondChange
    , onYearChange
    )


batch : List (Sub msg) -> Sub msg
batch =
    Sub.batch


onSecondChange : (Int -> msg) -> Sub msg
onSecondChange _ =
    Sub.none


onHourChange : (Int -> msg) -> Sub msg
onHourChange _ =
    Sub.none


onMinuteChange : (Int -> msg) -> Sub msg
onMinuteChange _ =
    Sub.none


onDayChange : (Int -> msg) -> Sub msg
onDayChange _ =
    Sub.none


onMonthChange : (Int -> msg) -> Sub msg
onMonthChange _ =
    Sub.none


onYearChange : (Int -> msg) -> Sub msg
onYearChange _ =
    Sub.none
