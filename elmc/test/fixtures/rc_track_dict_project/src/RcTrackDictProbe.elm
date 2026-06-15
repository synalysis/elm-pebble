module RcTrackDictProbe exposing
    ( probeDiff
    , probeEmpty
    , probeFilter
    , probeFoldl
    , probeFoldr
    , probeFromList
    , probeGet
    , probeInsert
    , probeIntersect
    , probeIsEmpty
    , probeKeys
    , probeMap
    , probeMember
    , probeMerge
    , probePartition
    , probeRemove
    , probeSingleton
    , probeSize
    , probeToList
    , probeUnion
    , probeUpdate
    , probeValues
    )

import Dict
import List
import Maybe


sample : Dict.Dict String Int
sample =
    Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ]


probeEmpty : Int
probeEmpty =
    Dict.size Dict.empty


probeSingleton : Int
probeSingleton =
    Dict.size (Dict.singleton "k" 1)


probeFromList : Int
probeFromList =
    Dict.size sample


probeInsert : Int
probeInsert =
    Dict.size (Dict.insert "c" 3 sample)


probeGet : Int
probeGet =
    Maybe.withDefault 0 (Dict.get "a" sample)


probeMember : Int
probeMember =
    if Dict.member "a" sample && not (Dict.member "z" sample) then
        1

    else
        0


probeSize : Int
probeSize =
    Dict.size sample


probeRemove : Int
probeRemove =
    Dict.size (Dict.remove "a" sample)


probeIsEmpty : Int
probeIsEmpty =
    if Dict.isEmpty Dict.empty && not (Dict.isEmpty sample) then
        1

    else
        0


probeKeys : Int
probeKeys =
    List.length (Dict.keys sample)


probeValues : Int
probeValues =
    List.sum (Dict.values sample)


probeToList : Int
probeToList =
    List.length (Dict.toList sample)


probeMap : Int
probeMap =
    Dict.size (Dict.map (\k v -> v + 1) sample)


probeFoldl : Int
probeFoldl =
    Dict.foldl (\k v acc -> acc + v) 0 sample


probeFoldr : Int
probeFoldr =
    Dict.foldr (\k v acc -> acc + v) 0 sample


probeFilter : Int
probeFilter =
    Dict.size (Dict.filter (\k v -> v > 1) sample)


probePartition : Int
probePartition =
    let
        ( yes, no ) =
            Dict.partition (\k v -> v > 1) sample
    in
    Dict.size yes + Dict.size no


probeUnion : Int
probeUnion =
    Dict.size (Dict.union sample (Dict.singleton "c" 3))


probeIntersect : Int
probeIntersect =
    Dict.size (Dict.intersect sample (Dict.fromList [ ( "a", 1 ), ( "c", 9 ) ]))


probeDiff : Int
probeDiff =
    Dict.size (Dict.diff sample (Dict.singleton "a" 0))


probeMerge : Int
probeMerge =
    Dict.size
        (Dict.merge
            (Dict.singleton "onlyLeft" 1)
            (Dict.singleton "onlyRight" 2)
            (\k left right -> left + right)
            (Dict.singleton "a" 1)
            (Dict.singleton "a" 10)
        )


probeUpdate : Int
probeUpdate =
    Dict.size (Dict.update "a" (\maybe -> Just 9) sample)
