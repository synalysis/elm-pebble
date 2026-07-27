module RcTrackRecordUpdateProbe exposing (probeAliasedBase, probeChainedUpdate, probeDictUpdateAlias)


import Dict


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


probeDictUpdateAlias : Int
probeDictUpdateAlias =
    let
        base =
            Dict.fromList [ ( "a", 1 ), ( "b", 2 ) ]

        updated =
            Dict.update "a" (\maybe -> Just 9) base
    in
    if Dict.size base == 2 then
        Maybe.withDefault 0 (Dict.get "a" updated)

    else
        0
