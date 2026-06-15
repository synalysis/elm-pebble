module RcTrackMaybeProbe exposing
    ( probeAndThen
    , probeMap
    , probeMap2
    , probeWithDefault
    )

import Maybe


justThree : Maybe Int
justThree =
    Just 3


probeWithDefault : Int
probeWithDefault =
    Maybe.withDefault 0 justThree


probeMap : Int
probeMap =
    Maybe.withDefault 0 (Maybe.map (\x -> x + 1) justThree)


probeMap2 : Int
probeMap2 =
    Maybe.withDefault 0 (Maybe.map2 (\a b -> a + b) (Just 1) (Just 2))


probeAndThen : Int
probeAndThen =
    Maybe.withDefault 0 (Maybe.andThen (\x -> Just (x * 2)) justThree)
