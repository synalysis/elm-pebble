module Main exposing (main)

import Array
import Dict
import Html exposing (Html, text)
import Json.Encode as Encode
import Set


main : Html String
main =
    let
        dictJson =
            Encode.encode 0
                (Encode.dict identity Encode.int (Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ]))

        setJson =
            Encode.encode 0 (Encode.set Encode.int (Set.fromList [ 1, 2 ]))

        listJson =
            Encode.encode 0 (Encode.list Encode.int [ 1, 2 ])

        arrayJson =
            Encode.encode 0 (Encode.array Encode.int (Array.fromList [ 3, 4 ]))
    in
    text (dictJson ++ " " ++ setJson ++ " " ++ listJson ++ " " ++ arrayJson)
