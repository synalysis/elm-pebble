module RcTrackBasicsProbe exposing
    ( probeAbs
    , probeAlways
    , probeClamp
    , probeCeiling
    , probeCompare
    , probeFloor
    , probeIdentity
    , probeMax
    , probeMin
    , probeModBy
    , probeNegate
    , probeNot
    , probeRemainderBy
    , probeRound
    , probeToFloat
    , probeTruncate
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
