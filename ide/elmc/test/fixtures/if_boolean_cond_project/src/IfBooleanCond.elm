module IfBooleanCond exposing (guarded, inverted)


guarded : Int -> Int -> Int
guarded a b =
    if a > 0 && b > 0 then
        1
    else
        0


inverted : Int -> Int -> Bool
inverted a b =
    not (a > 0 || b > 0)
