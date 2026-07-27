module BooleanPrecedence exposing (groupedAnd, orAnd)


orAnd : Int -> Int -> Int -> Bool
orAnd a b c =
    a > 0 || b > 0 && c > 0


groupedAnd : Int -> Int -> Int -> Bool
groupedAnd a b c =
    (a > 0 || b > 0) && c > 0
