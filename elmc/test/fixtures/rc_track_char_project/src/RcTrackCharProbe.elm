module RcTrackCharProbe exposing
    ( probeFromCode
    , probeIsAlpha
    , probeIsAlphaNum
    , probeIsDigit
    , probeIsHexDigit
    , probeIsLower
    , probeIsOctDigit
    , probeIsUpper
    , probeToCode
    , probeToLower
    , probeToUpper
    )


upperA : Char
upperA =
    'A'


lowerA : Char
lowerA =
    'a'


digitZero : Char
digitZero =
    '0'


hexChar : Char
hexChar =
    'f'


octChar : Char
octChar =
    '7'


probeToCode : Int
probeToCode =
    Char.toCode upperA


probeFromCode : Int
probeFromCode =
    Char.toCode (Char.fromCode 66)


probeIsUpper : Int
probeIsUpper =
    if Char.isUpper upperA && not (Char.isUpper lowerA) then
        1

    else
        0


probeIsLower : Int
probeIsLower =
    if Char.isLower lowerA && not (Char.isLower upperA) then
        1

    else
        0


probeIsAlpha : Int
probeIsAlpha =
    if Char.isAlpha upperA && Char.isAlpha lowerA then
        1

    else
        0


probeIsAlphaNum : Int
probeIsAlphaNum =
    if Char.isAlphaNum upperA && Char.isAlphaNum digitZero then
        1

    else
        0


probeIsDigit : Int
probeIsDigit =
    if Char.isDigit digitZero && not (Char.isDigit upperA) then
        1

    else
        0


probeIsOctDigit : Int
probeIsOctDigit =
    if Char.isOctDigit octChar then
        1

    else
        0


probeIsHexDigit : Int
probeIsHexDigit =
    if Char.isHexDigit hexChar && Char.isHexDigit digitZero then
        1

    else
        0


probeToUpper : Int
probeToUpper =
    Char.toCode (Char.toUpper lowerA)


probeToLower : Int
probeToLower =
    Char.toCode (Char.toLower upperA)
