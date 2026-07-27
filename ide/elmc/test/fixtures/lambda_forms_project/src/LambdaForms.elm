module LambdaForms exposing (ignorePayload, sumWithFold, zipAdd)


zipAdd : List Int -> List Int -> List Int
zipAdd left right =
    List.map2 (\x y -> x + y) left right


sumWithFold : List Int -> Int
sumWithFold values =
    List.foldl (\value acc -> acc + value) 0 values


ignorePayload : Maybe Int -> Int
ignorePayload maybeValue =
    Maybe.withDefault 0 (Maybe.map (\_ -> 1) maybeValue)
