module ConstructorPattern exposing (Pair(..), sumPair)


type Pair
    = Pair Int Int


sumPair : Pair -> Int
sumPair pair =
    case pair of
        Pair x y ->
            x + y
