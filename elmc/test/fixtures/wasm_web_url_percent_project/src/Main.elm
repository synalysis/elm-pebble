module Main exposing (main)

import Html exposing (Html, text)
import Url


showMaybe : Maybe String -> String
showMaybe value =
    case value of
        Just s ->
            "just:" ++ s

        Nothing ->
            "nothing"


main : Html String
main =
    text
        (String.join "|"
            [ Url.percentEncode "a b/c"
            , showMaybe (Url.percentDecode "a%20b")
            , showMaybe (Url.percentDecode "a+b")
            , showMaybe (Url.percentDecode "%")
            ]
        )
