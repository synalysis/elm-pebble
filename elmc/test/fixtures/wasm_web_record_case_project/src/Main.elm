module Main exposing (main)

import Html exposing (Html, text)


type alias Rec =
    { n : Int
    , label : String
    }


show : Rec -> String
show rec =
    case rec of
        { n, label } ->
            String.fromInt n ++ ":" ++ label

        _ ->
            "miss"


main : Html String
main =
    text
        (String.join "|"
            [ show { n = 1, label = "hi" }
            , show { n = 0, label = "z" }
            ]
        )
