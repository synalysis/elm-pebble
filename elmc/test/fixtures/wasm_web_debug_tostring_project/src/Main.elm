module Main exposing (main)

import Array
import Dict
import Html exposing (Html, text)
import Set


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


type Status
    = Idle
    | Ready Int


type Pair
    = Pair Int Int


type Triple
    = Triple Int Int Int


rec : { x : Int, y : Int }
rec =
    { x = 3, y = 4 }


main : Html String
main =
    text
        (String.join "|"
            [ "bt:" ++ flag (Debug.toString True == "True")
            , "bf:" ++ flag (Debug.toString False == "False")
            , "i:" ++ flag (Debug.toString 42 == "42")
            , "z:" ++ flag (Debug.toString 0 == "0")
            , "u:" ++ flag (Debug.toString () == "()")
            , "s:" ++ flag (Debug.toString "hi" == "\"hi\"")
            , "c:" ++ flag (Debug.toString 'A' == "'A'")
            , "cv:" ++ flag (Debug.toString (Char.fromCode 11) == "'\\v'")
            , "l:" ++ flag (Debug.toString [ 1, 2 ] == "[1,2]")
            , "t:" ++ flag (Debug.toString ( 3, 4 ) == "(3,4)")
            , "t3:" ++ flag (Debug.toString ( 1, 2, 3 ) == "(1,2,3)")
            , "tn:" ++ flag (Debug.toString ( 1, ( 2, 3 ) ) == "(1,(2,3))")
            , "tj:" ++ flag (Debug.toString ( 1, Just 2 ) == "(1,Just 2)")
            , "t3eq:" ++ flag (( 1, 2, 3 ) == ( 1, 2, 3 ) && ( 1, 2, 3 ) /= ( 1, 2, 4 ))
            , "j:" ++ flag (Debug.toString (Just 1) == "Just 1")
            , "n:" ++ flag (Debug.toString Nothing == "Nothing")
            , "ok:" ++ flag (Debug.toString (Ok 2) == "Ok 2")
            , "er:" ++ flag (Debug.toString (Err 3) == "Err 3")
            , "set:" ++ flag (Debug.toString (Set.fromList [ 1, 2 ]) == "Set.fromList [1,2]")
            , "dct:" ++ flag (Debug.toString (Dict.fromList [ ( "a", 1 ) ]) == "Dict.fromList [(\"a\",1)]")
            , "arr:" ++ flag (Debug.toString (Array.fromList [ 1, 2 ]) == "Array.fromList [1,2]")
            , "r:" ++ flag (Debug.toString { x = 3, y = 4 } == "{ x = 3, y = 4 }")
            , "ru:" ++ flag (Debug.toString { rec | y = 9 } == "{ x = 3, y = 9 }")
            , "id:" ++ flag (Debug.toString Idle == "Idle")
            , "rd:" ++ flag (Debug.toString (Ready 3) == "Ready 3")
            , "pr:" ++ flag (Debug.toString (Pair 1 2) == "Pair 1 2")
            , "tr:" ++ flag (Debug.toString (Triple 1 2 3) == "Triple 1 2 3")
            , "jt:" ++ flag (Debug.toString (Just ( 1, 2 )) == "Just (1,2)")
            , "eq:" ++ flag (Idle == Idle && Ready 1 == Ready 1 && Idle /= Ready 1 && Pair 1 2 == Pair 1 2)
            ]
        )
