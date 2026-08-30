module Main exposing (main)

import Html exposing (Html, div, text)
import Html.Attributes exposing (action, alt, class, classList, download, for, href, id, method, name, placeholder, rel, src, target, title, type_)


main : Html String
main =
    div
        [ id "root"
        , title "home"
        , href "https://elm-lang.org"
        , name "q"
        , placeholder "search"
        , type_ "text"
        , target "_blank"
        , rel "noreferrer"
        , alt "logo"
        , src "/logo.png"
        , download "notes.txt"
        , action "/submit"
        , method "post"
        , for "q"
        , class "wrap"
        , classList
            [ ( "on", True )
            , ( "off", False )
            , ( "also", True )
            ]
        ]
        [ text "ok" ]
