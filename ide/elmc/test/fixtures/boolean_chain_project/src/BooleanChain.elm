module BooleanChain exposing (allPositive, anyPositive)


allPositive : Int -> Int -> Int -> Bool
allPositive a b c =
    a > 0 && b > 0 && c > 0


anyPositive : Int -> Int -> Int -> Bool
anyPositive a b c =
    a > 0 || b > 0 || c > 0
