module RcTrackStringProbe exposing
    ( probeAll
    , probeAny
    , probeAppend
    , probeCons
    , probeContains
    , probeDropLeft
    , probeDropRight
    , probeEndsWith
    , probeFilter
    , probeFoldl
    , probeFoldr
    , probeFromChar
    , probeFromFloat
    , probeFromInt
    , probeFromList
    , probeIndexes
    , probeIsEmpty
    , probeJoin
    , probeLeft
    , probeLength
    , probeLines
    , probeMap
    , probePad
    , probePadLeft
    , probePadRight
    , probeRepeat
    , probeReplace
    , probeReverse
    , probeRight
    , probeSlice
    , probeSplit
    , probeSplitList
    , probeStartsWith
    , probeToFloat
    , probeToInt
    , probeToList
    , probeToListResult
    , probeToLower
    , probeToUpper
    , probeTrim
    , probeTrimLeft
    , probeTrimRight
    , probeUncons
    , probeWords
    )

import Char
import List
import Maybe


len : String -> Int
len value =
    String.length value


probeAppend : Int
probeAppend =
    len (String.append "ab" "cd")


probeIsEmpty : Int
probeIsEmpty =
    if String.isEmpty "" && not (String.isEmpty "a1B c2") then
        1

    else
        0


probeLength : Int
probeLength =
    String.length "a1B c2"


probeReverse : Int
probeReverse =
    len (String.reverse "a1B c2")


probeRepeat : Int
probeRepeat =
    len (String.repeat 2 "x")


probeReplace : Int
probeReplace =
    len (String.replace "a" "z" "aba")


probeFromInt : Int
probeFromInt =
    len (String.fromInt 42)


probeToInt : Int
probeToInt =
    Maybe.withDefault 0 (String.toInt "42")


probeFromFloat : Int
probeFromFloat =
    len (String.fromFloat 3.5)


probeToFloat : Int
probeToFloat =
    case String.toFloat "3.5" of
        Just _ ->
            1

        Nothing ->
            0


probeToUpper : Int
probeToUpper =
    len (String.toUpper "a1B c2")


probeToLower : Int
probeToLower =
    len (String.toLower "a1B c2")


probeTrim : Int
probeTrim =
    len (String.trim "  x  ")


probeTrimLeft : Int
probeTrimLeft =
    len (String.trimLeft "  x")


probeTrimRight : Int
probeTrimRight =
    len (String.trimRight "x  ")


probeContains : Int
probeContains =
    if String.contains "B" "a1B c2" then
        1

    else
        0


probeStartsWith : Int
probeStartsWith =
    if String.startsWith "a" "a1B c2" then
        1

    else
        0


probeEndsWith : Int
probeEndsWith =
    if String.endsWith "2" "a1B c2" then
        1

    else
        0


probeSplit : Int
probeSplit =
    List.length (String.split " " "a b c")


probeJoin : Int
probeJoin =
    len (String.join "-" [ "a", "b", "c" ])


probeWords : Int
probeWords =
    List.length (String.words "a b c")


probeLines : Int
probeLines =
    List.length (String.lines "a\nb\nc")


probeSlice : Int
probeSlice =
    len (String.slice 1 4 "a1B c2")


probeLeft : Int
probeLeft =
    len (String.left 2 "a1B c2")


probeRight : Int
probeRight =
    len (String.right 2 "a1B c2")


probeDropLeft : Int
probeDropLeft =
    len (String.dropLeft 1 "a1B c2")


probeDropRight : Int
probeDropRight =
    len (String.dropRight 1 "a1B c2")


probeCons : Int
probeCons =
    len (String.cons 'z' "ab")


probeUncons : Int
probeUncons =
    case String.uncons "a1B c2" of
        Just ( _, tail ) ->
            len tail

        Nothing ->
            -1


probeToList : Int
probeToList =
    List.length (String.toList "a1B c2")


probeFromList : Int
probeFromList =
    len (String.fromList [ 'a', 'b', 'c' ])


probeFromChar : Int
probeFromChar =
    len (String.fromChar 'x')


probePad : Int
probePad =
    len (String.pad 5 '0' "7")


probePadLeft : Int
probePadLeft =
    len (String.padLeft 5 '0' "7")


probePadRight : Int
probePadRight =
    len (String.padRight 5 '0' "7")


probeMap : Int
probeMap =
    len (String.map (\c -> Char.toUpper c) "a1B c2")


probeFilter : Int
probeFilter =
    len (String.filter (\c -> Char.isAlpha c) "a1B c2")


probeFoldl : Int
probeFoldl =
    String.foldl (\c acc -> acc + Char.toCode c) 0 "a1B c2"


probeFoldr : Int
probeFoldr =
    String.foldr (\c acc -> acc + Char.toCode c) 0 "a1B c2"


probeAny : Int
probeAny =
    if String.any (\c -> Char.isDigit c) "a1B c2" then
        1

    else
        0


probeAll : Int
probeAll =
    if String.all (\_ -> True) "a1B c2" then
        1

    else
        0


probeIndexes : Int
probeIndexes =
    List.length (String.indexes "a" "a1B c2")


probeSplitList : List String
probeSplitList =
    String.split " " "a1B c2"


probeToListResult : List Char
probeToListResult =
    String.toList "a1B c2"
