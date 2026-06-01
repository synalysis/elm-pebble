module CoreCompliance exposing
    ( arrayGetHit
    , arrayGetMiss
    , arrayGetNegative
    , arrayLengthFromList
    , arrayPushLength
    , arrayPushTwiceLastGet
    , arrayPushTwiceLength
    , arrayPushThenSetFirstGet
    , arraySetLastGet
    , arraySetThenSetGet
    , arraySetThenPushLastGet
    , arraySetInRangeGet
    , arraySetNegativeLength
    , arraySetOutOfRangeLength
    , branchTupleOut
    , branchTupleOutNested
    , bitwiseExtras
    , dictOverwriteGet
    , dictOverwriteSize
    , modByNeg
    , charCodeRoundtrip
    , charFromCode
    , constructorLiteralCase
    , constructorTripleCase
    , debugEcho
    , dictHasOne
    , dictLookupOne
    , dictFromListThenOverwriteGet
    , dictFromListThenOverwriteSize
    , dictFromListDuplicateGet
    , dictFromListDuplicateSize
    , dictSizeTwo
    , first
    , foldSum
    , fundamentalsMix
    , bitwiseMix
    , maybeInc
    , nestedTupleSum
    , nestedResult
    , resultInc
    , setHasThree
    , setFromListDuplicateHasTwo
    , setFromListDuplicateSize
    , setInsertDuplicateSize
    , setSizeAfterInsert
    , stringAppendLength
    , stringEmptyCheck
    , taskFailArg
    , taskFailInt
    , taskFailNested
    , processKillOk
    , processSpawnPidFromFail
    , processSpawnPidFromSucceed
    , processSleepOk
    , taskSucceedArg
    , taskSucceedInt
    , taskSucceedNested
    , second
    , stringLen
    , tuplePairFirst
    , tupleCase
    )

import Array
import Basics
import Bitwise
import Char
import Debug
import Dict
import List
import Maybe
import Process
import Result
import Set
import String
import Task
import Tuple


type TripleCheck
    = TripleCheck Int Int Int


foldSum : List Int -> Int
foldSum items =
    List.foldl (+) 0 items


maybeInc : Maybe Int -> Int
maybeInc maybeNumber =
    Maybe.withDefault 0 (Maybe.map ((+) 1) maybeNumber)


resultInc : Result String Int -> Int
resultInc resultValue =
    case resultValue of
        Ok value ->
            value + 1

        Err _ ->
            0


second : ( Int, Int ) -> Int
second tupleValue =
    Tuple.second tupleValue


first : ( Int, Int ) -> Int
first tupleValue =
    Tuple.first tupleValue


stringLen : String -> Int
stringLen value =
    String.length value


charFromCode : Int -> Char
charFromCode code =
    Char.fromCode code


charCodeRoundtrip : Int -> Int
charCodeRoundtrip code =
    Char.toCode (Char.fromCode code)


fundamentalsMix : Int -> Int -> Int
fundamentalsMix a b =
    Basics.clamp 0 10 (Basics.max a (Basics.min b 5))


bitwiseMix : Int -> Int
bitwiseMix value =
    Bitwise.xor (Bitwise.and value 3) (Bitwise.shiftLeftBy 1 (Bitwise.or value 2))


bitwiseExtras : Int -> Int
bitwiseExtras value =
    Bitwise.shiftRightZfBy 1 (Bitwise.complement value)


modByNeg : Int -> Int
modByNeg value =
    Basics.modBy 5 value


debugEcho : Int -> Int
debugEcho value =
    Debug.log "debugEcho" value


dictLookupOne : Maybe Int
dictLookupOne =
    Dict.get 1 (Dict.fromList [ ( 1, 10 ), ( 2, 20 ) ])


dictFromListDuplicateSize : Int
dictFromListDuplicateSize =
    Dict.size (Dict.fromList [ ( 1, 10 ), ( 1, 99 ), ( 2, 20 ) ])


dictFromListDuplicateGet : Maybe Int
dictFromListDuplicateGet =
    Dict.get 1 (Dict.fromList [ ( 1, 10 ), ( 1, 99 ), ( 2, 20 ) ])


dictFromListThenOverwriteSize : Int
dictFromListThenOverwriteSize =
    Dict.size (Dict.insert 1 123 (Dict.fromList [ ( 1, 10 ), ( 1, 99 ), ( 2, 20 ) ]))


dictFromListThenOverwriteGet : Maybe Int
dictFromListThenOverwriteGet =
    Dict.get 1 (Dict.insert 1 123 (Dict.fromList [ ( 1, 10 ), ( 1, 99 ), ( 2, 20 ) ]))


dictHasOne : Bool
dictHasOne =
    Dict.member 1 (Dict.fromList [ ( 1, 10 ), ( 2, 20 ) ])


dictSizeTwo : Int
dictSizeTwo =
    Dict.size (Dict.fromList [ ( 1, 10 ), ( 2, 20 ) ])


dictOverwriteSize : Int
dictOverwriteSize =
    Dict.size (Dict.insert 1 99 (Dict.fromList [ ( 1, 10 ), ( 2, 20 ) ]))


dictOverwriteGet : Maybe Int
dictOverwriteGet =
    Dict.get 1 (Dict.insert 1 99 (Dict.fromList [ ( 1, 10 ), ( 2, 20 ) ]))


setHasThree : Bool
setHasThree =
    Set.member 3 (Set.fromList [ 1, 2, 3 ])


setSizeAfterInsert : Int
setSizeAfterInsert =
    Set.size (Set.insert 4 (Set.fromList [ 1, 2, 3 ]))


setFromListDuplicateSize : Int
setFromListDuplicateSize =
    Set.size (Set.fromList [ 1, 2, 1, 3, 2 ])


setFromListDuplicateHasTwo : Bool
setFromListDuplicateHasTwo =
    Set.member 2 (Set.fromList [ 1, 2, 1, 3, 2 ])


setInsertDuplicateSize : Int
setInsertDuplicateSize =
    Set.size (Set.insert 3 (Set.fromList [ 1, 2, 3 ]))


arrayLengthFromList : Int
arrayLengthFromList =
    Array.length (Array.fromList [ 10, 20, 30 ])


arrayGetHit : Maybe Int
arrayGetHit =
    Array.get 1 (Array.fromList [ 10, 20, 30 ])


arrayGetMiss : Maybe Int
arrayGetMiss =
    Array.get 9 (Array.fromList [ 10, 20, 30 ])


arrayGetNegative : Maybe Int
arrayGetNegative =
    Array.get -1 (Array.fromList [ 10, 20, 30 ])


arraySetInRangeGet : Maybe Int
arraySetInRangeGet =
    Array.get 1 (Array.set 1 99 (Array.fromList [ 10, 20, 30 ]))


arraySetLastGet : Maybe Int
arraySetLastGet =
    Array.get 2 (Array.set 2 77 (Array.fromList [ 10, 20, 30 ]))


arraySetNegativeLength : Int
arraySetNegativeLength =
    Array.length (Array.set -1 99 (Array.fromList [ 10, 20, 30 ]))


arraySetOutOfRangeLength : Int
arraySetOutOfRangeLength =
    Array.length (Array.set 9 99 (Array.fromList [ 10, 20, 30 ]))


arrayPushLength : Int
arrayPushLength =
    Array.length (Array.push 40 (Array.fromList [ 10, 20, 30 ]))


arrayPushTwiceLength : Int
arrayPushTwiceLength =
    Array.length (Array.push 50 (Array.push 40 (Array.fromList [ 10, 20, 30 ])))


arrayPushTwiceLastGet : Maybe Int
arrayPushTwiceLastGet =
    Array.get 4 (Array.push 50 (Array.push 40 (Array.fromList [ 10, 20, 30 ])))


arraySetThenPushLastGet : Maybe Int
arraySetThenPushLastGet =
    Array.get 3 (Array.push 40 (Array.set 1 99 (Array.fromList [ 10, 20, 30 ])))


arraySetThenSetGet : Maybe Int
arraySetThenSetGet =
    Array.get 1 (Array.set 1 55 (Array.set 1 99 (Array.fromList [ 10, 20, 30 ])))


arrayPushThenSetFirstGet : Maybe Int
arrayPushThenSetFirstGet =
    Array.get 0 (Array.set 0 77 (Array.push 40 (Array.fromList [ 10, 20, 30 ])))


taskSucceedInt : Task.Task Int Int
taskSucceedInt =
    Task.succeed 7


taskFailInt : Task.Task Int Int
taskFailInt =
    Task.fail 5


taskSucceedArg : Int -> Task.Task Int Int
taskSucceedArg value =
    Task.succeed value


taskFailArg : Int -> Task.Task Int Int
taskFailArg value =
    Task.fail value


taskSucceedNested : Task.Task Int (Task.Task Int Int)
taskSucceedNested =
    Task.succeed (Task.fail 9)


taskFailNested : Task.Task (Task.Task Int Int) Int
taskFailNested =
    Task.fail (Task.succeed 11)


processSpawnPidFromSucceed : Int
processSpawnPidFromSucceed =
    let task = Process.spawn (Task.succeed 1) in
    case task of
        Ok pid ->
            pid

        Err _ ->
            -1


processSpawnPidFromFail : Int
processSpawnPidFromFail =
    let task = Process.spawn (Task.fail 2) in
    case task of
        Ok pid ->
            pid

        Err _ ->
            -1


processSleepOk : Int
processSleepOk =
    let task = Process.sleep 5 in
    case task of
        Ok _ ->
            1

        Err _ ->
            0


processKillOk : Int
processKillOk =
    let task = Process.kill 1 in
    case task of
        Ok _ ->
            1

        Err _ ->
            0


stringAppendLength : String -> String -> Int
stringAppendLength left right =
    let appended = String.append left right in
    String.length appended


stringEmptyCheck : String -> Bool
stringEmptyCheck value =
    String.isEmpty value


tuplePairFirst : Int -> Int -> Int
tuplePairFirst left right =
    Tuple.first (Tuple.pair left right)


nestedResult : Result String (Maybe Int) -> Int
nestedResult value =
    case value of
        Ok (Just n) ->
            n + 1

        Ok Nothing ->
            0

        Err _ ->
            0


tupleCase : ( Result String Int, Maybe Int ) -> Int
tupleCase pair =
    case pair of
        ( Ok n, Just m ) ->
            n + m

        ( Ok n, Nothing ) ->
            n

        _ ->
            0


nestedTupleSum : ( ( Int, Int ), Maybe Int ) -> Int
nestedTupleSum value =
    case value of
        ( ( left, right ), _ ) ->
            left + right


branchTupleOut : ( Result String Int, Maybe Int ) -> ( Int, Int )
branchTupleOut value =
    case value of
        ( Ok n, Just m ) ->
            ( n, m )

        ( Ok n, Nothing ) ->
            ( n, 0 )

        _ ->
            ( 0, 0 )


branchTupleOutNested : Result String (Maybe Int) -> ( Int, Int )
branchTupleOutNested value =
    case value of
        Ok (Just n) ->
            ( n, n + 1 )

        Ok Nothing ->
            ( 0, 0 )

        Err _ ->
            ( 0, 0 )


constructorLiteralCase : Int
constructorLiteralCase =
    let triple = TripleCheck 2 3 0 in
    case triple of
        TripleCheck 1 y _ ->
            y

        TripleCheck x y _ ->
            x + y


constructorTripleCase : Int
constructorTripleCase =
    let triple = TripleCheck 1 2 3 in
    case triple of
        TripleCheck 1 middle right ->
            middle + right

        TripleCheck _ _ _ ->
            0
