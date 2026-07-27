module Main exposing (main)

import Html exposing (Html, div, text)


mapBody : List (Html msg) -> List (Html msg)
mapBody =
    List.map (Html.map identity)


main : Html msg
main =
    div []
        (mapBody
            [ div [] [ text "header" ]
            , div [] [ text "main" ]
            , div [] [ text "footer" ]
            ]
        )
