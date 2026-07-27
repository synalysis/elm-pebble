module ArithmeticChain exposing (mixedChain, sumThree)


sumThree : Int -> Int -> Int -> Int
sumThree a b c =
    a + b + c


mixedChain : Int -> Int -> Int -> Int
mixedChain a b c =
    a + b - c
