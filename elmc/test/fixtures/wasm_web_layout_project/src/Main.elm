module Main exposing (main)

import Html exposing (a, div, footer, header, main_, p, text)
import Html.Attributes exposing (class, href)


main =
    div [ class "page" ]
        [ header [ class "site-header" ] [ text "Elm Pebble" ]
        , main_ [] [ p [] [ text "Hello from WASM" ] ]
        , footer [ class "site-footer" ]
            [ a [ href "/docs", class "link" ] [ text "Docs" ] ]
        ]
