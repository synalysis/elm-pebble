module RcTrackArrayProbe exposing
    ( probeAppend
    , probeEmpty
    , probeFilter
    , probeFoldl
    , probeFoldr
    , probeFromList
    , probeGet
    , probeIndexedMap
    , probeInitialize
    , probeIsEmpty
    , probeLength
    , probeMap
    , probePush
    , probeRepeat
    , probeSet
    , probeSetAlias
    , probeSlice
    , probeToIndexedList
    , probeToList
    , probeToListResult
    )

import Array
import List
import Maybe


probeEmpty : Int
probeEmpty =
    Array.length Array.empty


probeFromList : Int
probeFromList =
    Array.length (Array.fromList [ 10, 20, 30 ])


probeLength : Int
probeLength =
    Array.length (Array.fromList [ 1, 2, 3, 4 ])


probeGet : Int
probeGet =
    Maybe.withDefault -1 (Array.get 1 (Array.fromList [ 10, 20, 30 ]))


probeSet : Int
probeSet =
    Maybe.withDefault -1 (Array.get 1 (Array.set 1 99 (Array.fromList [ 10, 20, 30 ])))


probePush : Int
probePush =
    Array.length (Array.push 40 (Array.fromList [ 10, 20, 30 ]))


probeInitialize : Int
probeInitialize =
    Array.foldl (\x acc -> acc + x) 0 (Array.initialize 3 (\i -> i + 1))


probeRepeat : Int
probeRepeat =
    Array.foldl (\x acc -> acc + x) 0 (Array.repeat 3 7)


probeIsEmpty : Int
probeIsEmpty =
    if Array.isEmpty Array.empty && not (Array.isEmpty (Array.fromList [ 1 ])) then
        1

    else
        0


probeToList : Int
probeToList =
    List.length (Array.toList (Array.fromList [ 1, 2, 3 ]))


probeToIndexedList : Int
probeToIndexedList =
    List.length (Array.toIndexedList (Array.fromList [ 1, 2, 3 ]))


probeMap : Int
probeMap =
    Array.foldl (\x acc -> acc + x) 0 (Array.map (\x -> x + 1) (Array.fromList [ 1, 2, 3 ]))


probeIndexedMap : Int
probeIndexedMap =
    Array.foldl (\x acc -> acc + x) 0 (Array.indexedMap (\i x -> i + x) (Array.fromList [ 1, 2, 3 ]))


probeFoldl : Int
probeFoldl =
    Array.foldl (\x acc -> acc + x) 0 (Array.fromList [ 1, 2, 3 ])


probeFoldr : Int
probeFoldr =
    Array.foldr (\x acc -> acc + x) 0 (Array.fromList [ 1, 2, 3 ])


probeFilter : Int
probeFilter =
    Array.length (Array.filter (\x -> x > 1) (Array.fromList [ 1, 2, 3 ]))


probeAppend : Int
probeAppend =
    Array.length (Array.append (Array.fromList [ 1, 2 ]) (Array.fromList [ 3, 4 ]))


probeSlice : Int
probeSlice =
    Array.length (Array.slice 1 3 (Array.fromList [ 1, 2, 3, 4, 5 ]))


baseArray : Array.Array Int
baseArray =
    Array.fromList [ 10, 20, 30 ]


probeSetAlias : Int
probeSetAlias =
    let
        updated =
            Array.set 1 99 baseArray
    in
    Maybe.withDefault -1 (Array.get 1 updated)
        + Maybe.withDefault -1 (Array.get 1 baseArray)


probeToListResult : List Int
probeToListResult =
    Array.toList baseArray
