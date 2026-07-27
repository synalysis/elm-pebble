module RcTrackBitwiseProbe exposing
    ( probeAnd
    , probeComplement
    , probeOr
    , probeShiftLeftBy
    , probeShiftRightBy
    , probeShiftRightZfBy
    , probeXor
    )

import Bitwise


probeAnd : Int
probeAnd =
    Bitwise.and 5 3


probeOr : Int
probeOr =
    Bitwise.or 5 3


probeXor : Int
probeXor =
    Bitwise.xor 5 3


probeComplement : Int
probeComplement =
    Bitwise.and (Bitwise.complement 5) 7


probeShiftLeftBy : Int
probeShiftLeftBy =
    Bitwise.shiftLeftBy 1 3


probeShiftRightBy : Int
probeShiftRightBy =
    Bitwise.shiftRightBy 1 6


probeShiftRightZfBy : Int
probeShiftRightZfBy =
    Bitwise.shiftRightZfBy 1 6
