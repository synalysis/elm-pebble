module Main exposing (main)

import Html exposing (Html, text)


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


sum3 : ( Int, Int, Int ) -> Int
sum3 triple =
    let
        ( a, b, c ) =
            triple
    in
    a + b + c


match12 : ( Int, Int ) -> Bool
match12 pair =
    case pair of
        ( 1, 2 ) ->
            True

        _ ->
            False


match123 : ( Int, Int, Int ) -> Bool
match123 triple =
    case triple of
        ( 1, 2, 3 ) ->
            True

        _ ->
            False


main : Html String
main =
    text
        (String.join "|"
            [ "tf:" ++ flag (Tuple.first ( 1, "a" ) == 1)
            , "ts:" ++ flag (Tuple.second ( 1, "a" ) == "a")
            , "tp:" ++ flag (Tuple.pair 1 "a" == ( 1, "a" ))
            , "mf:" ++ flag (Tuple.mapFirst String.length ( "cat", 2 ) == ( 3, 2 ))
            , "ms:" ++ flag (Tuple.mapSecond String.length ( 2, "cat" ) == ( 2, 3 ))
            , "mb:" ++ flag (Tuple.mapBoth String.length (\n -> n + 1) ( "ab", 3 ) == ( 2, 4 ))
            , "c3:" ++ flag (compare ( 1, 2, 3 ) ( 1, 2, 4 ) == LT && compare ( 1, 2, 3 ) ( 1, 2, 3 ) == EQ && compare ( 2, 0, 0 ) ( 1, 9, 0 ) == GT)
            , "s3:" ++ flag (List.sort [ ( 2, 0, 0 ), ( 1, 9, 0 ), ( 1, 2, 3 ) ] == [ ( 1, 2, 3 ), ( 1, 9, 0 ), ( 2, 0, 0 ) ])
            , "l3:" ++ flag (sum3 ( 9, 8, 7 ) == 24)
            , "k2:" ++ flag (match12 ( 1, 2 ) && not (match12 ( 1, 3 )))
            , "k3:" ++ flag (match123 ( 1, 2, 3 ))
            , "k3n:" ++ flag (not (match123 ( 1, 2, 4 )))
            ]
        )
