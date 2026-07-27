module Main exposing (main)

import Html exposing (Html, div, node, text)
import Html.Attributes exposing (class, href, rel, target)


wrap : Html msg -> Html msg
wrap =
    Html.map identity


main =
    wrap <|
        div [ class "page" ]
            [ node "details" [ class "menu" ]
                [ node "summary" [] [ text "Menu" ]
                , a [ href "https://example.com", target "_blank", rel "noreferrer" ] [ text "Link" ]
                ]
            , div [] [ text " mapped" ]
            ]
