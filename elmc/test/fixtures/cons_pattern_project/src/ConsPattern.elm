module ConsPattern exposing (headPlusTailCount)


headPlusTailCount : List Int -> Int
headPlusTailCount values =
    case values of
        x :: xs ->
            x + List.length xs

        [] ->
            0
