module RcTrackSetProbe exposing
    ( probeDiff
    , probeEmpty
    , probeFilter
    , probeFoldl
    , probeFoldr
    , probeFromList
    , probeInsert
    , probeIntersect
    , probeIsEmpty
    , probeMap
    , probeMember
    , probePartition
    , probeRemove
    , probeSingleton
    , probeSize
    , probeToList
    , probeUnion
    )

import List
import Set


sample : Set.Set Int
sample =
    Set.fromList [ 1, 2, 3 ]


probeEmpty : Int
probeEmpty =
    Set.size Set.empty


probeSingleton : Int
probeSingleton =
    Set.size (Set.singleton 7)


probeFromList : Int
probeFromList =
    Set.size sample


probeInsert : Int
probeInsert =
    Set.size (Set.insert 4 sample)


probeMember : Int
probeMember =
    if Set.member 2 sample && not (Set.member 9 sample) then
        1

    else
        0


probeSize : Int
probeSize =
    Set.size sample


probeRemove : Int
probeRemove =
    Set.size (Set.remove 2 sample)


probeIsEmpty : Int
probeIsEmpty =
    if Set.isEmpty Set.empty && not (Set.isEmpty sample) then
        1

    else
        0


probeToList : Int
probeToList =
    List.length (Set.toList sample)


probeUnion : Int
probeUnion =
    Set.size (Set.union sample (Set.singleton 4))


probeIntersect : Int
probeIntersect =
    Set.size (Set.intersect sample (Set.fromList [ 2, 9 ]))


probeDiff : Int
probeDiff =
    Set.size (Set.diff sample (Set.singleton 2))


probeMap : Int
probeMap =
    Set.size (Set.map (\x -> x + 1) sample)


probeFoldl : Int
probeFoldl =
    Set.foldl (\x acc -> acc + x) 0 sample


probeFoldr : Int
probeFoldr =
    Set.foldr (\x acc -> acc + x) 0 sample


probeFilter : Int
probeFilter =
    Set.size (Set.filter (\x -> x > 1) sample)


probePartition : Int
probePartition =
    let
        ( yes, no ) =
            Set.partition (\x -> x > 1) sample
    in
    Set.size yes + Set.size no
