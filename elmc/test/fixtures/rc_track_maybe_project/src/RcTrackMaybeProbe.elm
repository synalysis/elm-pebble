module RcTrackMaybeProbe exposing
    ( probeAndThen
    , probeAndThenNothing
    , probeMap
    , probeMap2
    , probeMapNothing
    , probeWithDefault
    , probeWithDefaultNothing
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


probeWithDefaultNothing : Int
probeWithDefaultNothing =
    Maybe.withDefault 7 Nothing


probeMapNothing : Int
probeMapNothing =
    Maybe.withDefault 0 (Maybe.map (\x -> x + 1) Nothing)


probeAndThenNothing : Int
probeAndThenNothing =
    Maybe.withDefault 0 (Maybe.andThen (\x -> Just (x * 2)) Nothing)
