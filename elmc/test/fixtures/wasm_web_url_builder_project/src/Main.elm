module Main exposing (main)

import Html exposing (Html, text)
import Url.Builder as Builder


main : Html String
main =
    text
        (String.join "|"
            [ Builder.absolute [] []
            , Builder.absolute [ "packages", "elm", "core" ] []
            , Builder.absolute [ "products" ] [ Builder.string "search" "hat", Builder.int "page" 2 ]
            , Builder.relative [] []
            , Builder.relative [ "elm", "core" ] []
            , Builder.crossOrigin "https://example.com" [ "products" ] []
            , Builder.crossOrigin "https://example.com" [] []
            , Builder.custom Builder.Absolute [ "packages", "elm", "core", "latest", "String" ] [] (Just "length")
            , Builder.custom Builder.Relative [ "there" ] [ Builder.string "name" "ferret" ] Nothing
            , Builder.custom
                (Builder.CrossOrigin "https://example.com:8042")
                [ "over", "there" ]
                [ Builder.string "name" "ferret" ]
                (Just "nose")
            , Builder.toQuery [ Builder.string "search" "coffee table" ]
            , Builder.toQuery []
            ]
        )
