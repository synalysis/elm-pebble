module RcTrackCompareProbe exposing (probeListEqual, probeRecordEqual)


type alias Pair =
    { left : List Int
    , right : List Int
    }


probeListEqual : Int
probeListEqual =
    let
        first =
            [ 1, 2, 3, 4 ]

        second =
            first
    in
    if first == second then
        1

    else
        0


probeRecordEqual : Int
probeRecordEqual =
    let
        pair =
            { left = [ 1, 0, 1 ], right = [ 1, 0, 1 ] }

        same =
            pair
    in
    if pair == same then
        1

    else
        0
