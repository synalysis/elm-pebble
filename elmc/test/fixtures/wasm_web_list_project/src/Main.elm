module Main exposing (main)

import Html exposing (Html, text)


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


emptyFloatSum : Float
emptyFloatSum =
    List.sum []


emptyFloatProduct : Float
emptyFloatProduct =
    List.product []


emptyFloats : List Float
emptyFloats =
    []


labelEmptyFloatSum : String
labelEmptyFloatSum =
    String.fromFloat (List.sum emptyFloats)


labelEmptyFloatProduct : String
labelEmptyFloatProduct =
    String.fromFloat (List.product emptyFloats)


flippedComparison : comparable -> comparable -> Order
flippedComparison a b =
    case compare a b of
        LT ->
            GT

        EQ ->
            EQ

        GT ->
            LT


main : Html String
main =
    text
        (String.join "|"
            [ "tk:" ++ flag (List.take 2 [ 1, 2, 3, 4 ] == [ 1, 2 ])
            , "t0:" ++ flag (List.take 0 [ 1, 2, 3, 4 ] == [])
            , "tn:" ++ flag (List.take -1 [ 1, 2, 3, 4 ] == [])
            , "dr:" ++ flag (List.drop 2 [ 1, 2, 3, 4 ] == [ 3, 4 ])
            , "d0:" ++ flag (List.drop 0 [ 1, 2, 3, 4 ] == [ 1, 2, 3, 4 ])
            , "dn:" ++ flag (List.drop -1 [ 1, 2, 3, 4 ] == [ 1, 2, 3, 4 ])
            , "rg:" ++ flag (List.range 3 6 == [ 3, 4, 5, 6 ])
            , "re:" ++ flag (List.range 6 3 == [])
            , "rp:" ++ flag (List.repeat 3 7 == [ 7, 7, 7 ])
            , "r0:" ++ flag (List.repeat 0 7 == [])
            , "in:" ++ flag (List.intersperse 0 [ 1, 2, 3 ] == [ 1, 0, 2, 0, 3 ])
            , "ins:" ++ flag (List.intersperse "on" [ "turtles", "turtles", "turtles" ] == [ "turtles", "on", "turtles", "on", "turtles" ])
            , "uz:" ++ flag (List.unzip [ ( 0, True ), ( 17, False ), ( 1337, True ) ] == ( [ 0, 17, 1337 ], [ True, False, True ] ))
            , "pt:" ++ flag (List.partition (\x -> x < 3) [ 0, 1, 2, 3, 4, 5 ] == ( [ 0, 1, 2 ], [ 3, 4, 5 ] ))
            , "m2:" ++ flag (List.map2 (+) [ 1, 2, 3 ] [ 4, 5, 6 ] == [ 5, 7, 9 ])
            , "m2s:" ++ flag (List.map2 Tuple.pair [ "alice", "bob", "chuck" ] [ 2, 5, 7, 8 ] == [ ( "alice", 2 ), ( "bob", 5 ), ( "chuck", 7 ) ])
            , "st:" ++ flag (List.sort [ 3, 1, 5 ] == [ 1, 3, 5 ])
            , "ss:" ++ flag (List.sort [ "b", "a", "c" ] == [ "a", "b", "c" ])
            , "st2:" ++ flag (List.sort [ ( 2, "b" ), ( 1, "a" ), ( 1, "c" ) ] == [ ( 1, "a" ), ( 1, "c" ), ( 2, "b" ) ])
            , "sl:" ++ flag (List.sort [ [ 2 ], [ 1, 9 ], [ 1, 2 ] ] == [ [ 1, 2 ], [ 1, 9 ], [ 2 ] ])
            , "sb:" ++ flag (List.sortBy String.length [ "mouse", "cat" ] == [ "cat", "mouse" ])
            , "fm:" ++ flag (List.filterMap String.toInt [ "3", "hi", "12", "4th", "May" ] == [ 3, 12 ])
            , "pr:" ++ flag (List.product [] == 1)
            , "cc:" ++ flag (List.concat [ [ 1, 2 ], [ 3 ], [ 4, 5 ] ] == [ 1, 2, 3, 4, 5 ])
            , "mb:" ++ flag (List.member 4 [ 1, 2, 3, 4 ] && not (List.member 9 [ 1, 2, 3, 4 ]))
            , "sm:" ++ flag (List.sum [ 1, 2, 3 ] == 6 && List.sum [] == 0)
            , "sf:" ++ flag (List.sum [ 1.5, 2.5 ] == 4.0)
            , "pf:" ++ flag (List.product [ 2.0, 3.0 ] == 6.0)
            , "mx:" ++ flag (List.maximum [ 1, 4, 2 ] == Just 4 && List.maximum [] == Nothing)
            , "mn:" ++ flag (List.minimum [ 3, 2, 1 ] == Just 1)
            , "mxs:" ++ flag (List.maximum [ "b", "a", "c" ] == Just "c")
            , "hd:" ++ flag (List.head [ 1, 2 ] == Just 1)
            , "tl:" ++ flag (List.tail [ 1, 2, 3 ] == Just [ 2, 3 ])
            , "im:" ++ flag (List.indexedMap Tuple.pair [ "Tom", "Sue", "Bob" ] == [ ( 0, "Tom" ), ( 1, "Sue" ), ( 2, "Bob" ) ])
            , "cm:" ++ flag (List.concatMap (List.repeat 2) [ 1, 2 ] == [ 1, 1, 2, 2 ])
            , "sw:" ++ flag (List.sortWith flippedComparison [ 1, 2, 3, 4, 5 ] == [ 5, 4, 3, 2, 1 ])
            , "ap:" ++ flag (List.append [ 1, 1, 2 ] [ 3, 5, 8 ] == [ 1, 1, 2, 3, 5, 8 ])
            , "rv:" ++ flag (List.reverse [ 1, 2, 3 ] == [ 3, 2, 1 ])
            , "m3:" ++ flag (List.map3 (\a b c -> a + b + c) [ 1, 2 ] [ 1, 1, 1 ] [ 1, 1 ] == [ 3, 4 ])
            , "m4:" ++ flag (List.map4 (\a b c d -> a + b + c + d) [ 1 ] [ 1 ] [ 1 ] [ 1 ] == [ 4 ])
            , "m5:" ++ flag (List.map5 (\a b c d e -> a + b + c + d + e) [ 1 ] [ 1 ] [ 1 ] [ 1 ] [ 1 ] == [ 5 ])
            , "sfe:" ++ flag (List.sum [] == 0.0)
            , "pfe:" ++ flag (List.product [] == 1.0)
            , "sft:" ++ flag (emptyFloatSum == 0.0)
            , "pft:" ++ flag (emptyFloatProduct == 1.0)
            , "sxf:" ++ labelEmptyFloatSum
            , "pxf:" ++ labelEmptyFloatProduct
            , "ie:" ++ flag (List.isEmpty [] && not (List.isEmpty [ 1 ]))
            , "ln:" ++ flag (List.length [ 1, 2, 3 ] == 3 && List.length [] == 0)
            , "sg:" ++ flag (List.singleton 1234 == [ 1234 ])
            , "mp:" ++ flag (List.map (\n -> n * 2) [ 1, 2, 3 ] == [ 2, 4, 6 ])
            , "fl:" ++ flag (List.filter (\n -> remainderBy 2 n == 0) [ 1, 2, 3, 4 ] == [ 2, 4 ])
            , "fdl:" ++ flag (List.foldl (::) [] [ 1, 2, 3 ] == [ 3, 2, 1 ])
            , "fdr:" ++ flag (List.foldr (::) [] [ 1, 2, 3 ] == [ 1, 2, 3 ])
            , "al:" ++ flag (List.all (\n -> n > 0) [ 1, 2 ] && not (List.all (\n -> n > 0) [ 1, 0 ]))
            , "ay:" ++ flag (List.any (\n -> n > 2) [ 1, 3 ] && not (List.any (\n -> n > 4) [ 1, 3 ]))
            ]
        )
