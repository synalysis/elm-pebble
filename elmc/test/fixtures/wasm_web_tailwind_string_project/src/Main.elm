module Main exposing (main)

import Html exposing (div, text)
import Tailwind exposing (classes, dark, gray, md, px, s3, s700, shrink_0, text_color)


main =
    div
        [ classes
            [ shrink_0
            , px s3
            , md [ px s3 ]
            , dark [ text_color (gray s700) ]
            ]
        ]
        [ text "ok" ]
