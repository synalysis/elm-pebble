module ListPattern exposing (isEmptyAsInt)


isEmptyAsInt : List Int -> Int
isEmptyAsInt values =
    case values of
        [] ->
            1

        _ ->
            0
