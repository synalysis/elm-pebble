module Main exposing (main)

import Html exposing (Html, text)
import Url


proto : Url.Protocol -> String
proto protocol =
    case protocol of
        Url.Http ->
            "http"

        Url.Https ->
            "https"


maybeInt : Maybe Int -> String
maybeInt value =
    case value of
        Just n ->
            String.fromInt n

        Nothing ->
            "n"


maybeStr : Maybe String -> String
maybeStr value =
    case value of
        Just s ->
            s

        Nothing ->
            "n"


show : Maybe Url.Url -> String
show maybeUrl =
    case maybeUrl of
        Nothing ->
            "nothing"

        Just url ->
            String.join ","
                [ proto url.protocol
                , url.host
                , maybeInt url.port_
                , url.path
                , maybeStr url.query
                , maybeStr url.fragment
                , Url.toString url
                ]


main : Html String
main =
    text
        (String.join "|"
            [ show (Url.fromString "https://example.com:443")
            , show (Url.fromString "https://example.com/hats?q=top%20hat")
            , show (Url.fromString "http://example.com/core/List/#map")
            , show (Url.fromString "example.com:443")
            , show (Url.fromString "http://tom@example.com")
            , show (Url.fromString "http://#cats")
            ]
        )
