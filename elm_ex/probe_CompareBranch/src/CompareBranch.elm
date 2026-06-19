module CompareBranch exposing (main)

{-| Test compare result via case expression.

Expected output: "less"
-}


main =
    case compare "rD" "rS" of
        LT ->
            "less"

        EQ ->
            "equal"

        GT ->
            "greater"
