module AsPattern exposing (headAndLength)


headAndLength : List Int -> Int
headAndLength values =
    case values of
        (x :: xs) as full ->
            x + List.length full

        [] ->
            0
