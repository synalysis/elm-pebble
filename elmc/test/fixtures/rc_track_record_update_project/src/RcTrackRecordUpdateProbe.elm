module RcTrackRecordUpdateProbe exposing (probeAliasedBase, probeChainedUpdate)


type alias Model =
    { values : List Int
    , total : Int
    , best : Int
    , seed : Int
    , turn : Int
    }


baseModel : Model
baseModel =
    { values = [ 1, 2, 3, 4 ]
    , total = 10
    , best = 10
    , seed = 7
    , turn = 0
    }


probeChainedUpdate : Int
probeChainedUpdate =
    let
        updated =
            { baseModel
                | values = [ 4, 3, 2, 1 ]
                , total = 20
                , best = 20
                , seed = 11
                , turn = baseModel.turn + 1
            }
    in
    updated.total + updated.best + updated.seed + updated.turn


probeAliasedBase : Int
probeAliasedBase =
    let
        model =
            baseModel

        updated =
            { model | total = model.total + 1, turn = model.turn + 1 }
    in
    if model.values == updated.values then
        updated.total

    else
        0
