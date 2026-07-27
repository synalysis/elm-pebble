module RcTrack2048Probe exposing (initialModel, leftMove, modelTurn, step)

import List
import Maybe


type alias Model =
    { cells : List Int
    , score : Int
    , best : Int
    , seed : Int
    , turn : Int
    }


type Direction
    = Left
    | Right
    | Up
    | Down


type alias CollapseResult =
    { cells : List Int
    , score : Int
    }


initialModel : Int -> Model
initialModel seed =
    let
        ( cells, nextSeed ) =
            initialBoard seed
    in
    { cells = cells
    , score = 0
    , best = 0
    , seed = nextSeed
    , turn = 0
    }


leftMove : Model -> Model
leftMove model =
    moveBoard Left model


step : Int -> Model -> Model
step dir model =
    case dir of
        1 ->
            moveBoard Right model

        2 ->
            moveBoard Up model

        3 ->
            moveBoard Down model

        _ ->
            moveBoard Left model


modelTurn : Model -> Int
modelTurn model =
    model.turn


moveBoard : Direction -> Model -> Model
moveBoard direction model =
    let
        oriented =
            orient direction model.cells

        collapsed =
            collapseRows oriented

        restored =
            restore direction collapsed.cells
    in
    if restored == model.cells then
        model

    else
        let
            ( nextCells, nextSeed ) =
                spawnTileWithSeed model.seed restored

            nextScore =
                model.score + collapsed.score

            nextBest =
                max model.best nextScore
        in
        { model
            | cells = nextCells
            , score = nextScore
            , best = nextBest
            , seed = nextSeed
            , turn = model.turn + 1
        }


initialBoard : Int -> ( List Int, Int )
initialBoard seed =
    let
        ( firstCells, firstSeed ) =
            spawnTileWithSeed seed emptyBoard
    in
    spawnTileWithSeed firstSeed firstCells


emptyBoard : List Int
emptyBoard =
    List.repeat 16 0


collapseRows : List Int -> CollapseResult
collapseRows cells =
    let
        row0 =
            collapseRow (rowAt 0 cells)

        row1 =
            collapseRow (rowAt 1 cells)

        row2 =
            collapseRow (rowAt 2 cells)

        row3 =
            collapseRow (rowAt 3 cells)
    in
    { cells = row0.cells ++ row1.cells ++ row2.cells ++ row3.cells
    , score = row0.score + row1.score + row2.score + row3.score
    }


collapseRow : List Int -> CollapseResult
collapseRow row =
    let
        merged =
            merge (List.filter ((/=) 0) row)
    in
    { cells = merged.cells ++ List.repeat (4 - List.length merged.cells) 0
    , score = merged.score
    }


merge : List Int -> CollapseResult
merge values =
    case values of
        a :: b :: rest ->
            if a == b then
                let
                    tail =
                        merge rest

                    value =
                        a + b
                in
                { cells = value :: tail.cells
                , score = value + tail.score
                }

            else
                let
                    tail =
                        merge (b :: rest)
                in
                { cells = a :: tail.cells
                , score = tail.score
                }

        _ ->
            { cells = values, score = 0 }


spawnTileWithSeed : Int -> List Int -> ( List Int, Int )
spawnTileWithSeed seed cells =
    let
        emptyCount =
            countEmpty cells

        seedAfterChoice =
            advanceSeed seed

        seedAfterTile =
            advanceSeed seedAfterChoice

        tileIndex =
            nthEmptyIndex (randomIndex emptyCount seedAfterChoice) cells

        tileValue =
            if randomIndex 10 seedAfterTile == 0 then
                4

            else
                2
    in
    if emptyCount == 0 then
        ( cells, seedAfterTile )

    else
        ( setCell tileIndex tileValue cells, seedAfterTile )


advanceSeed : Int -> Int
advanceSeed seed =
    modBy 2147483647 (seed * 16807 + 11)


randomIndex : Int -> Int -> Int
randomIndex maxExclusive seed =
    if maxExclusive <= 0 then
        0

    else
        modBy maxExclusive seed


countEmpty : List Int -> Int
countEmpty cells =
    case cells of
        [] ->
            0

        value :: rest ->
            (if value == 0 then
                1

             else
                0
            )
                + countEmpty rest


nthEmptyIndex : Int -> List Int -> Int
nthEmptyIndex target cells =
    nthEmptyIndexHelp target 0 cells


nthEmptyIndexHelp : Int -> Int -> List Int -> Int
nthEmptyIndexHelp target index cells =
    case cells of
        [] ->
            -1

        value :: rest ->
            if value == 0 then
                if target == 0 then
                    index

                else
                    nthEmptyIndexHelp (target - 1) (index + 1) rest

            else
                nthEmptyIndexHelp target (index + 1) rest


setCell : Int -> Int -> List Int -> List Int
setCell index newValue cells =
    List.indexedMap
        (\i value ->
            if i == index then
                newValue

            else
                value
        )
        cells


orient : Direction -> List Int -> List Int
orient direction cells =
    case direction of
        Left ->
            cells

        Right ->
            reverseRows cells

        Up ->
            transpose cells

        Down ->
            reverseRows (transpose cells)


restore : Direction -> List Int -> List Int
restore direction cells =
    case direction of
        Left ->
            cells

        Right ->
            reverseRows cells

        Up ->
            transpose cells

        Down ->
            transpose (reverseRows cells)


rowAt : Int -> List Int -> List Int
rowAt row cells =
    List.take 4 (List.drop (row * 4) cells)


reverseRows : List Int -> List Int
reverseRows cells =
    [ List.reverse (rowAt 0 cells)
    , List.reverse (rowAt 1 cells)
    , List.reverse (rowAt 2 cells)
    , List.reverse (rowAt 3 cells)
    ]
        |> List.concat


transpose : List Int -> List Int
transpose cells =
    List.map
        (\i -> Maybe.withDefault 0 (listAt i cells))
        [ 0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15 ]


listAt : Int -> List a -> Maybe a
listAt index values =
    if index < 0 then
        Nothing

    else
        List.head (List.drop index values)
