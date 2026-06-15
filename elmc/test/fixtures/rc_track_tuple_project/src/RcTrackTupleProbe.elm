module RcTrackTupleProbe exposing
    ( probeFirst
    , probeMapBoth
    , probeMapFirst
    , probeMapSecond
    , probePair
    , probeSecond
    )

import Tuple


probeFirst : Int
probeFirst =
    Tuple.first ( 1, 2 )


probeSecond : Int
probeSecond =
    Tuple.second ( 1, 2 )


probePair : Int
probePair =
    Tuple.first (Tuple.pair 3 4)


probeMapFirst : Int
probeMapFirst =
    Tuple.first (Tuple.mapFirst (\x -> x + 1) ( 1, 2 ))


probeMapSecond : Int
probeMapSecond =
    Tuple.second (Tuple.mapSecond (\y -> y + 2) ( 1, 2 ))


probeMapBoth : Int
probeMapBoth =
    let
        ( left, right ) =
            Tuple.mapBoth (\x -> x + 1) (\y -> y + 2) ( 1, 2 )
    in
    left + right
