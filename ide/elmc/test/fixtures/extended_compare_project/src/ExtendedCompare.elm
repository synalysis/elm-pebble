module ExtendedCompare exposing (gteCheck, lteCheck, notEqualCheck)


gteCheck : Int -> Int -> Bool
gteCheck a b =
    a >= b


lteCheck : Int -> Int -> Bool
lteCheck a b =
    a <= b


notEqualCheck : Int -> Int -> Bool
notEqualCheck a b =
    a /= b
