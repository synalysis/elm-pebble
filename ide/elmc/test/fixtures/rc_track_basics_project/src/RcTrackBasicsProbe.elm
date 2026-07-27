module RcTrackBasicsProbe exposing
    ( probeAbs
    , probeAcos
    , probeAlways
    , probeAsin
    , probeAtan
    , probeAtan2
    , probeClamp
    , probeCeiling
    , probeCompare
    , probeCos
    , probeDegrees
    , probeFloor
    , probeFromPolar
    , probeIdentity
    , probeIsInfinite
    , probeIsNan
    , probeLogBase
    , probeMax
    , probeMin
    , probeModBy
    , probeNegate
    , probeNot
    , probeRadians
    , probeRemainderBy
    , probeRound
    , probeSin
    , probeSqrt
    , probeTan
    , probeToFloat
    , probeToPolar
    , probeTruncate
    , probeTurns
    , probeXor
    )

import Basics exposing (..)


probeMax : Int
probeMax =
    max 3 7


probeMin : Int
probeMin =
    min 3 7


probeClamp : Int
probeClamp =
    clamp 1 10 15


probeModBy : Int
probeModBy =
    modBy 3 10


probeIdentity : Int
probeIdentity =
    List.sum (List.map (\x -> x) [ 1, 2, 3 ])


probeAlways : Int
probeAlways =
    always 99 0


probeNot : Int
probeNot =
    if not False then
        1

    else
        0


probeNegate : Int
probeNegate =
    negate -4


probeAbs : Int
probeAbs =
    abs -6


probeToFloat : Int
probeToFloat =
    truncate (toFloat 9)


probeRound : Int
probeRound =
    round 3.6


probeFloor : Int
probeFloor =
    floor 3.9


probeCeiling : Int
probeCeiling =
    ceiling 3.1


probeTruncate : Int
probeTruncate =
    truncate 3.9


probeRemainderBy : Int
probeRemainderBy =
    remainderBy 3 10


probeXor : Int
probeXor =
    if xor True False then
        1

    else
        0


probeCompare : Int
probeCompare =
    let
        a =
            compare 1 2

        b =
            compare 2 2

        c =
            compare 3 2
    in
    (if a == LT then 1 else 0)
        + (if b == EQ then 10 else 0)
        + (if c == GT then 100 else 0)


probeSqrt : Int
probeSqrt =
    truncate (sqrt 16)


probeSin : Int
probeSin =
    round (sin 0)


probeCos : Int
probeCos =
    round (cos 0)


probeTan : Int
probeTan =
    truncate (tan 0)


probeAsin : Int
probeAsin =
    truncate (asin 0)


probeAcos : Int
probeAcos =
    truncate (acos 1)


probeAtan : Int
probeAtan =
    truncate (atan 1)


probeAtan2 : Int
probeAtan2 =
    truncate (atan2 1 1)


probeDegrees : Int
probeDegrees =
    truncate (degrees pi)


probeRadians : Int
probeRadians =
    truncate (radians 180)


probeTurns : Int
probeTurns =
    truncate (turns 1)


probeLogBase : Int
probeLogBase =
    truncate (logBase 2 8)


probeIsNan : Int
probeIsNan =
    if isNaN (0 / 0) then
        1

    else
        0


probeIsInfinite : Int
probeIsInfinite =
    if isInfinite (1 / 0) then
        1

    else
        0


probeFromPolar : Int
probeFromPolar =
    let
        ( x, y ) =
            fromPolar ( 5, 0 )
    in
    truncate x + truncate y


probeToPolar : Int
probeToPolar =
    let
        ( r, _ ) =
            toPolar ( 3, 4 )
    in
    truncate r
