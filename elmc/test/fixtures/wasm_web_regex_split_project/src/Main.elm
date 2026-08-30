module Main exposing (main)

import Html exposing (Html, text)
import Regex


show : List String -> String
show parts =
    String.join "/" parts


main : Html String
main =
    case Regex.fromStringWith { caseInsensitive = True, multiline = False } "ab" of
        Nothing ->
            text "fail-ins"

        Just ins ->
            case Regex.fromStringWith { caseInsensitive = False, multiline = True } "^x" of
                Nothing ->
                    text "fail-multi"

                Just multi ->
                    case Regex.fromStringWith { caseInsensitive = False, multiline = False } "[" of
                        Just _ ->
                            text "fail-bad"

                        Nothing ->
                            case Regex.fromString "," of
                                Nothing ->
                                    text "fail-comma"

                                Just re ->
                                    text
                                        (String.join "|"
                                            [ show (List.map .match (Regex.find ins "xxAByy"))
                                            , show (List.map .match (Regex.find multi "a\nx"))
                                            , show (Regex.split re "a,b,c")
                                            , show (Regex.splitAtMost 0 re "a,b,c")
                                            , show (Regex.splitAtMost 1 re "a,b,c")
                                            ]
                                        )
