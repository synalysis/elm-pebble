module Main exposing (main)

import Dict
import Html exposing (Html, text)
import Set


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


just : Maybe Int -> String
just value =
    case value of
        Just n ->
            String.fromInt n

        Nothing ->
            "0"


main : Html String
main =
    let
        set =
            Set.fromList [ 1, 2, 2, 3 ]

        dict =
            Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ]

        ( kept, dropped ) =
            Set.partition (\n -> n > 1) set

        merged =
            Dict.merge
                (\k v acc -> acc ++ k ++ String.fromInt v)
                (\k a b acc -> acc ++ k ++ String.fromInt (a + b))
                (\k v acc -> acc ++ k ++ String.fromInt v)
                dict
                (Dict.fromList [ ( "b", 10 ), ( "c", 3 ) ])
                ""
    in
    text
        (String.join "|"
            [ "sm:" ++ flag (Set.member 2 set && not (Set.member 9 set))
            , "ss:" ++ String.fromInt (Set.size set)
            , "su:" ++ String.fromInt (Set.size (Set.union set (Set.singleton 4)))
            , "sp:" ++ String.fromInt (Set.size kept) ++ String.fromInt (Set.size dropped)
            , "dg:" ++ just (Dict.get "b" dict)
            , "du:" ++ just (Dict.get "a" (Dict.update "a" (Maybe.map (\n -> n + 5)) dict))
            , "dm:" ++ merged
            , "sd:" ++ flag (Set.toList (Set.diff (Set.fromList [ 1, 2, 3 ]) (Set.fromList [ 3, 4 ])) == [ 1, 2 ])
            , "si:" ++ flag (Set.toList (Set.intersect (Set.fromList [ 1, 2, 3 ]) (Set.fromList [ 3, 4 ])) == [ 3 ])
            , "sf:" ++ flag (Set.toList (Set.filter (\n -> remainderBy 2 n == 0) (Set.fromList [ 1, 2, 3, 4 ])) == [ 2, 4 ])
            , "smap:" ++ flag (Set.toList (Set.map (\n -> n * 2) (Set.fromList [ 1, 2 ])) == [ 2, 4 ])
            , "dd:" ++ flag (Dict.toList (Dict.diff (Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ]) (Dict.fromList [ ( "b", 9 ) ])) == [ ( "a", 1 ) ])
            , "di:" ++ flag (Dict.toList (Dict.intersect (Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ]) (Dict.fromList [ ( "b", 9 ), ( "c", 3 ) ])) == [ ( "b", 2 ) ])
            , "df:" ++ flag (Dict.toList (Dict.filter (\k _ -> k == "a") (Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ])) == [ ( "a", 1 ) ])
            , "dmap:" ++ flag (Dict.toList (Dict.map (\_ v -> v * 2) (Dict.fromList [ ( "a", 1 ) ])) == [ ( "a", 2 ) ])
            , "dk:" ++ flag (Dict.keys dict == [ "a", "b" ])
            , "dv:" ++ flag (Dict.values dict == [ 1, 2 ])
            , "de:" ++ flag (Dict.isEmpty Dict.empty && not (Dict.isEmpty dict))
            , "dmb:" ++ flag (Dict.member "a" dict && not (Dict.member "z" dict))
            , "se:" ++ flag (Set.isEmpty Set.empty && not (Set.isEmpty set))
            , "si2:" ++ flag (Set.member 9 (Set.insert 9 set))
            , "srm:" ++ flag (not (Set.member 1 (Set.remove 1 set)))
            , "stl:" ++ flag (Set.toList set == [ 1, 2, 3 ])
            , "sfl:" ++ flag (Set.foldl (+) 0 set == 6)
            , "sfr:" ++ flag (Set.foldr (::) [] set == [ 1, 2, 3 ])
            , "dun:" ++ flag (Dict.toList (Dict.union (Dict.fromList [ ( "a", 1 ) ]) (Dict.fromList [ ( "b", 2 ) ])) == [ ( "a", 1 ), ( "b", 2 ) ])
            , "dpt:" ++ flag (Dict.toList (Tuple.first (Dict.partition (\k _ -> k == "a") dict)) == [ ( "a", 1 ) ])
            , "din:" ++ flag (Dict.get "c" (Dict.insert "c" 3 dict) == Just 3)
            , "drm:" ++ flag (Dict.get "a" (Dict.remove "a" dict) == Nothing)
            , "dsn:" ++ flag (Dict.get "k" (Dict.singleton "k" 9) == Just 9)
            , "dsz:" ++ flag (Dict.size dict == 2)
            , "dfl:" ++ flag (Dict.foldl (\k v acc -> acc ++ k ++ String.fromInt v) "" dict == "a1b2")
            , "dfr:" ++ flag (Dict.foldr (\k v acc -> acc ++ k ++ String.fromInt v) "" dict == "b2a1")
            ]
        )
