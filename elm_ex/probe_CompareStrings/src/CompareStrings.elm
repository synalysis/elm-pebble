module CompareStrings exposing (main)

{-| Test Basics.compare for strings - critical for Dict/Set.

Expected output: "EQ LT GT"
-}


main =
    let
        eq = compare "abc" "abc"
        lt = compare "abc" "xyz"
        gt = compare "xyz" "abc"
    in
    Debug.toString eq ++ " " ++ Debug.toString lt ++ " " ++ Debug.toString gt
