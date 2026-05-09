module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Light as Light
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Random


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


type Msg
    = LeftPressed
    | RightPressed
    | UpPressed
    | DownPressed
    | BestLoaded String
    | RandomGenerated Int


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { cells = emptyBoard
      , score = 0
      , best = 0
      , seed = 0
      , turn = 0
      }
    , Cmd.batch
        [ Storage.readString 2048 BestLoaded
        , Random.generate RandomGenerated (Random.int 1 2147483647)
        , Light.enable
        ]
    )


emptyBoard : List Int
emptyBoard =
    List.repeat 16 0


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LeftPressed ->
            moveBoard Left model

        RightPressed ->
            moveBoard Right model

        UpPressed ->
            moveBoard Up model

        DownPressed ->
            moveBoard Down model

        BestLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )

        RandomGenerated seed ->
            let
                ( cells, nextSeed ) =
                    initialBoard seed
            in
            ( { model | cells = cells, seed = nextSeed }, Cmd.none )


moveBoard : Direction -> Model -> ( Model, Cmd Msg )
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
        ( model, Cmd.none )

    else
        let
            ( nextCells, nextSeed ) =
                spawnTileWithSeed model.seed restored

            nextScore =
                model.score + collapsed.score

            nextBest =
                max model.best nextScore

            saveBest =
                if nextBest > model.best then
                    Storage.writeString 2048 (String.fromInt nextBest)

                else
                    Cmd.none
        in
        ( { model
            | cells = nextCells
            , score = nextScore
            , best = nextBest
            , seed = nextSeed
            , turn = model.turn + 1
          }
        , saveBest
        )


initialBoard : Int -> ( List Int, Int )
initialBoard seed =
    let
        ( firstCells, firstSeed ) =
            spawnTileWithSeed seed emptyBoard
    in
    spawnTileWithSeed firstSeed firstCells


type alias CollapseResult =
    { cells : List Int
    , score : Int
    }


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


spawnTile : Int -> List Int -> List Int
spawnTile seed cells =
    Tuple.first (spawnTileWithSeed seed cells)


spawnTileWithSeed : Int -> List Int -> ( List Int, Int )
spawnTileWithSeed seed cells =
    let
        emptyIndexes =
            indexedEmptyCells cells

        seedAfterChoice =
            advanceSeed seed

        seedAfterTile =
            advanceSeed seedAfterChoice

        tileIndex =
            Maybe.withDefault -1 (listAt (randomIndex (List.length emptyIndexes) seedAfterChoice) emptyIndexes)

        tileValue =
            if randomIndex 10 seedAfterTile == 0 then
                4

            else
                2
    in
    if emptyIndexes == [] then
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


indexedEmptyCells : List Int -> List Int
indexedEmptyCells cells =
    cells
        |> List.indexedMap
            (\index value ->
                if value == 0 then
                    index

                else
                    -1
            )
        |> List.filter ((<=) 0)


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


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Back LeftPressed
        , Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        , Button.onPress Button.Select RightPressed
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        ([ Ui.clear Color.white
         , Ui.text Resources.DefaultFont { x = 4, y = 4, w = 132, h = 16 } ("2048  Best " ++ String.fromInt model.best)
         , Ui.text Resources.DefaultFont { x = 4, y = 20, w = 132, h = 12 } "Back L  Up U  Sel R  Down D"
         ]
            ++ List.indexedMap drawCell model.cells
        )


drawCell : Int -> Int -> Ui.RenderOp
drawCell index value =
    let
        x =
            10 + modBy 4 index * 31

        y =
            42 + (index // 4) * 31

        label =
            if value == 0 then
                "."

            else
                String.fromInt value
    in
    Ui.group
        (Ui.context
            [ Ui.strokeColor Color.black
            , Ui.textColor Color.black
            ]
            [ Ui.rect { x = x, y = y, w = 28, h = 28 } Color.black
            , Ui.text Resources.DefaultFont { x = x + 2, y = y + 5, w = 24, h = 18 } label
            ]
        )


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
