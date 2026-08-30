module Main exposing (main)

import Bitwise
import Html exposing (Html, text)


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


near : Float -> Float -> Bool
near got want =
    abs (got - want) < 0.001


main : Html String
main =
    text
        (String.join "|"
            [ "deg:" ++ flag (near (degrees 180) pi)
            , "rad:" ++ flag (near (radians 2) 2)
            , "trn:" ++ flag (near (turns 1) (2 * pi))
            , "pol:" ++ flag (near (Tuple.first (fromPolar ( 1, 0 ))) 1 && near (Tuple.second (fromPolar ( 1, 0 ))) 0)
            , "tp:" ++ flag (near (Tuple.first (toPolar ( 3, 4 ))) 5 && near (Tuple.second (toPolar ( 3, 4 ))) (atan2 4 3))
            , "sn:" ++ flag (near (sin (degrees 90)) 1 && near (cos 0) 1)
            , "at2:" ++ flag (near (atan2 1 0) (pi / 2))
            , "mb:" ++ flag (modBy 4 5 == 1)
            , "mn:" ++ flag (modBy 4 -5 == 3)
            , "mbn:" ++ flag (modBy -4 5 == -3)
            , "mbnn:" ++ flag (modBy -4 -5 == -1)
            , "rb:" ++ flag (remainderBy 4 -5 == -1)
            , "cl:" ++ flag (clamp 0 10 15 == 10 && clamp 0 10 -2 == 0 && clamp 0 10 7 == 7)
            , "mm:" ++ flag (min 3 1 == 1 && max 3 1 == 3)
            , "ba:" ++ flag (Bitwise.and 15 7 == 7)
            , "bo:" ++ flag (Bitwise.or 8 1 == 9)
            , "bx:" ++ flag (Bitwise.xor 15 7 == 8)
            , "bc:" ++ flag (Bitwise.complement 0 == -1)
            , "bl:" ++ flag (Bitwise.shiftLeftBy 2 8 == 32)
            , "br:" ++ flag (Bitwise.shiftRightBy 2 -32 == -8)
            , "bz:" ++ flag (Bitwise.shiftRightZfBy 1 -1 == 2147483647)
            , "id:" ++ flag (identity 7 == 7)
            , "alw:" ++ flag (always 4 5 == 4)
            , "nt:" ++ flag (not True == False && not False == True)
            , "xr:" ++ flag (xor True False && not (xor True True) && not (xor False False))
            , "ng:" ++ flag (negate 2 == -2 && negate -3 == 3)
            , "ab:" ++ flag (abs -2 == 2)
            , "tf:" ++ flag (toFloat 2 == 2.0)
            , "rd:" ++ flag (round 1.5 == 2 && round -1.5 == -1)
            , "flr:" ++ flag (floor 1.9 == 1 && floor -1.1 == -2)
            , "ce:" ++ flag (ceiling 1.1 == 2 && ceiling -1.1 == -1)
            , "tr:" ++ flag (truncate 1.9 == 1 && truncate -1.9 == -1)
            , "nan:" ++ flag (isNaN (0.0 / 0.0) && not (isNaN 1.0))
            , "inf:" ++ flag (isInfinite (1.0 / 0.0) && not (isInfinite (0.0 / 0.0)) && not (isInfinite 1.0))
            , "lb:" ++ flag (near (logBase 10 100) 2)
            , "sq:" ++ flag (near (sqrt 4) 2)
            , "cmp:" ++ flag (compare 3 1 == GT && compare 2 2 == EQ && compare 1 3 == LT)
            , "ord:" ++ flag (LT == LT && EQ /= GT)
            ]
        )
