module Main exposing (main)

import Html exposing (Html, text)
import Regex


main : Html String
main =
    case Regex.fromString "ab" of
        Just regex ->
            let
                found =
                    Regex.find regex "xxabyyab"

                replaced =
                    Regex.replace regex
                        (\m -> String.fromInt m.number ++ String.fromInt m.index ++ m.match)
                        "xxabyyab"

                foundOne =
                    Regex.findAtMost 1 regex "xxabyyab"

                replacedOne =
                    Regex.replaceAtMost 1 regex (\_ -> "X") "xxabyyab"
            in
            if
                List.map .match found
                    == [ "ab", "ab" ]
                    && replaced
                    == "xx12abyy26ab"
                    && List.map .match foundOne
                    == [ "ab" ]
                    && replacedOne
                    == "xxXyyab"
            then
                text "ok"

            else
                text "fail"

        Nothing ->
            text "fail"
