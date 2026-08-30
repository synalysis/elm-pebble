module Main exposing (main)

import Array
import Html exposing (Html, text)


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


nums : Array.Array Int -> String
nums array =
    String.join "," (List.map String.fromInt (Array.toList array))


indexed : ( Int, Int ) -> String
indexed ( i, x ) =
    String.fromInt i ++ ":" ++ String.fromInt x


main : Html String
main =
    let
        base =
            Array.fromList [ 10, 20, 30 ]
    in
    text
        (String.join "|"
            [ "empty:" ++ flag (Array.isEmpty Array.empty)
            , "get:" ++ just (Array.get 1 base)
            , "miss:" ++ just (Array.get 9 base) ++ just (Array.get -1 base)
            , "set:" ++ just (Array.get 1 (Array.set 1 99 base))
            , "len:" ++ String.fromInt (Array.length (Array.push 40 base))
            , "init:" ++ String.fromInt (Array.foldl (+) 0 (Array.initialize 3 (\i -> i + 1)))
            , "rep:" ++ nums (Array.repeat 2 7)
            , "app:" ++ nums (Array.append (Array.fromList [ 1, 2 ]) (Array.fromList [ 3 ]))
            , "sl:" ++ nums (Array.slice 1 3 (Array.fromList [ 1, 2, 3, 4 ]))
            , "sln:" ++ nums (Array.slice 2 -1 (Array.fromList [ 0, 1, 2, 3, 4 ]))
            , "sle:" ++ flag (Array.toList (Array.slice 3 1 (Array.fromList [ 0, 1, 2, 3, 4 ])) == [])
            , "soob:" ++ flag (Array.toList (Array.set 9 99 (Array.fromList [ 1, 2, 3 ])) == [ 1, 2, 3 ])
            , "map:" ++ nums (Array.map (\x -> x + 1) (Array.fromList [ 1, 2 ]))
            , "fil:" ++ String.fromInt (Array.length (Array.filter (\x -> x > 1) (Array.fromList [ 1, 2, 3 ])))
            , "fr:" ++ String.fromInt (Array.foldr (\x acc -> acc + x) 0 (Array.fromList [ 1, 2, 3 ]))
            , "im:" ++ nums (Array.indexedMap (\i x -> i + x) (Array.fromList [ 10, 20 ]))
            , "ix:" ++ String.join "," (List.map indexed (Array.toIndexedList (Array.fromList [ 5, 6 ])))
            ]
        )
