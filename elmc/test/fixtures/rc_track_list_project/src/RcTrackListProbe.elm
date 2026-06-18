module RcTrackListProbe exposing
    ( probeAll
    , probeAny
    , probeAppend
    , probeAppendChain
    , probeConcat
    , probeConcatMap
    , probeCons
    , probeConsChain
    , probeDrop
    , probeFilter
    , probeFilterMap
    , probeFoldl
    , probeFoldr
    , probeHead
    , probeIndexedMap
    , probeIntersperse
    , probeIsEmpty
    , probeLength
    , probeMap
    , probeMap2
    , probeMap3
    , probeMaximum
    , probeMember
    , probeMinimum
    , probePartition
    , probeProduct
    , probeRange
    , probeRepeat
    , probeReverse
    , probeReverseList
    , probeSingleton
    , probeSort
    , probeSortBy
    , probeSortWith
    , probeSum
    , probeTail
    , probeTake
    , probeUnzip
    )

import List
import Maybe


{-| Sample list used across probes.
-}
sample : List Int
sample =
    [ 1, 2, 3, 4 ]


{-| Reduce list result to Int for host checksum probes.
-}
listChecksum : List Int -> Int
listChecksum items =
    List.sum items + List.length items


probeIsEmpty : Int
probeIsEmpty =
    if List.isEmpty [] && not (List.isEmpty sample) then
        1

    else
        0


probeLength : Int
probeLength =
    List.length sample


probeHead : Int
probeHead =
    Maybe.withDefault 0 (List.head sample)


probeTail : Int
probeTail =
    case List.tail sample of
        Just tail ->
            List.length tail

        Nothing ->
            -1


probeReverse : Int
probeReverse =
    listChecksum (List.reverse sample)


probeReverseList : List Int
probeReverseList =
    List.reverse sample


probeMember : Int
probeMember =
    if List.member 3 sample && not (List.member 9 sample) then
        1

    else
        0


probeMap : Int
probeMap =
    List.sum (List.map (\x -> x + 1) sample)


probeFilter : Int
probeFilter =
    List.sum (List.filter (\x -> x > 2) sample)


probeFoldl : Int
probeFoldl =
    List.foldl (+) 0 sample


probeFoldr : Int
probeFoldr =
    List.foldr (\x acc -> x + acc) 0 sample


probeAppend : Int
probeAppend =
    listChecksum (List.append [ 1, 2 ] [ 3, 4 ])


probeConcat : Int
probeConcat =
    listChecksum (List.concat [ [ 1, 2 ], [ 3 ], [ 4, 5 ] ])


probeConcatMap : Int
probeConcatMap =
    listChecksum (List.concatMap (\x -> [ x, x ]) [ 1, 2 ])


probeIndexedMap : Int
probeIndexedMap =
    List.sum (List.indexedMap (\i x -> i + x) sample)


probeFilterMap : Int
probeFilterMap =
    List.sum (List.filterMap (\x -> if x > 1 then Just x else Nothing) sample)


probeSum : Int
probeSum =
    List.sum sample


probeProduct : Int
probeProduct =
    List.product sample


probeMaximum : Int
probeMaximum =
    Maybe.withDefault 0 (List.maximum sample)


probeMinimum : Int
probeMinimum =
    Maybe.withDefault 0 (List.minimum sample)


probeAny : Int
probeAny =
    if List.any (\x -> x > 3) sample then
        1

    else
        0


probeAll : Int
probeAll =
    if List.all (\x -> x > 0) sample then
        1

    else
        0


probeSort : Int
probeSort =
    listChecksum (List.sort [ 4, 1, 3, 2 ])


probeSortBy : Int
probeSortBy =
    listChecksum (List.sortBy (\x -> x) [ 4, 1, 3, 2 ])


probeSortWith : Int
probeSortWith =
    listChecksum (List.sortWith (\a b -> compare a b) [ 4, 1, 3, 2 ])


probeSingleton : Int
probeSingleton =
    listChecksum (List.singleton 7)


probeRange : Int
probeRange =
    List.sum (List.range 1 5)


probeRepeat : Int
probeRepeat =
    List.sum (List.repeat 3 2)


probeTake : Int
probeTake =
    List.sum (List.take 2 sample)


probeDrop : Int
probeDrop =
    List.sum (List.drop 1 sample)


probePartition : Int
probePartition =
    let
        ( yes, no ) =
            List.partition (\x -> x > 2) sample
    in
    List.length yes + List.length no


probeUnzip : Int
probeUnzip =
    let
        ( left, right ) =
            List.unzip [ ( 1, 2 ), ( 3, 4 ), ( 5, 6 ) ]
    in
    List.sum left + List.sum right


probeIntersperse : Int
probeIntersperse =
    listChecksum (List.intersperse 0 [ 1, 2, 3 ])


probeMap2 : Int
probeMap2 =
    List.sum (List.map2 (\a b -> a + b) [ 1, 2, 3 ] [ 4, 5, 6 ])


probeMap3 : Int
probeMap3 =
    List.sum (List.map3 (\a b c -> a + b + c) [ 1, 2 ] [ 3, 4 ] [ 5, 6 ])


probeCons : Int
probeCons =
    listChecksum (0 :: sample)


probeConsChain : Int
probeConsChain =
    listChecksum (List.cons 0 (List.cons 9 (List.reverse sample)))


probeAppendChain : Int
probeAppendChain =
    listChecksum (List.append sample (List.reverse (List.take 2 sample)))
