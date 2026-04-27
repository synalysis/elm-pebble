module SyntaxEdge exposing
    ( Model
    , backtickMod
    , pipelineSum
    , recordUpdate
    )

import List

type alias Model =
    { value : Int
    , values : List Int
    }

pipelineSum : List Int -> Int
pipelineSum values =
    values
        |> List.map ((+) 1)
        |> List.foldl (+) 0

backtickMod : Int -> Int
backtickMod value =
    modBy 10 value

recordUpdate : Model -> Model
recordUpdate model =
    { model
        | value = model.value + 1
        , values = model.values
    }
