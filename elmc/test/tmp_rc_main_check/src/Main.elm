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
    , screenW : Int
    , screenH : Int
    , displayShape : Platform.DisplayShape
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
init context =
    ( { cells = emptyBoard
      , score = 0
      , best = 0
      , seed = 0
      , turn = 0
      , screenW = context.screen.width
      , screenH = context.screen.height
      , displayShape = context.screen.shape
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
    let
        layout =
            boardLayout model

        textOptions =
            if Platform.displayShapeIsRound model.displayShape then
                Ui.alignCenter Ui.defaultTextOptions

            else
                Ui.defaultTextOptions

        chromeOps =
            if Platform.displayShapeIsRound model.displayShape then
                let
                    textW =
                        (min model.screenW model.screenH * 4) // 9

                    textX =
                        (model.screenW - textW) // 2
                in
                [ Ui.text Resources.DefaultFont textOptions { x = textX, y = 10, w = textW, h = 14 } "2048"
                , Ui.text Resources.DefaultFont textOptions { x = textX, y = model.screenH - 24, w = textW, h = 14 } ("Best " ++ String.fromInt model.best)
                ]

            else
                [ Ui.text Resources.DefaultFont textOptions { x = 4, y = 4, w = 132, h = 16 } ("2048  Best " ++ String.fromInt model.best)
                ]
    in
    Ui.clear Color.white
        :: (chromeOps
                ++ List.indexedMap (drawCell layout) model.cells
           )
        |> Ui.toUiNode


type alias BoardLayout =
    { x : Int
    , y : Int
    , cell : Int
    , gap : Int
    }


boardLayout : Model -> BoardLayout
boardLayout model =
    if Platform.displayShapeIsRound model.displayShape then
        let
            diameter =
                min model.screenW model.screenH

            targetBoardSize =
                (diameter * 2) // 3

            gap =
                2

            cell =
                (targetBoardSize - gap * 3) // 4

            boardSize =
                cell * 4 + gap * 3
        in
        { x = (model.screenW - boardSize) // 2
        , y = (model.screenH - boardSize) // 2
        , cell = cell
        , gap = gap
        }

    else
        let
            -- Rectangular watches are always taller than wide; use the physical
            -- panel axes so layout stays correct even if screenW/screenH are swapped.
            panelWidth =
                min model.screenW model.screenH

            boardTop =
                26

            horizontalMargin =
                12

            bottomMargin =
                4

            -- Ui.rect (x,y,w,h) is the outer inked bounds; keep symmetric screen padding.
            outlinePad =
                3

            gap =
                3

            availableW =
                panelWidth - horizontalMargin * 2 - outlinePad * 2

            -- Horizontal extent is the binding constraint on rect watches.
            targetBoardSize =
                availableW

            cell =
                (targetBoardSize - gap * 3) // 4

            boardWidth =
                cell * 4 + gap * 3
        in
        { x = (panelWidth - boardWidth) // 2
        , y = boardTop
        , cell = cell
        , gap = gap
        }


drawCell : BoardLayout -> Int -> Int -> Ui.RenderOp
drawCell layout index value =
    let
        x =
            layout.x + modBy 4 index * (layout.cell + layout.gap)

        y =
            layout.y + (index // 4) * (layout.cell + layout.gap)

        label =
            if value == 0 then
                "."

            else
                String.fromInt value

        textY =
            y + ((layout.cell - 18) // 2)
    in
    Ui.context
        [ Ui.strokeColor Color.black
        , Ui.textColor Color.black
        ]
        [ Ui.rect { x = x, y = y, w = layout.cell, h = layout.cell } Color.black
        , Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = x, y = textY, w = layout.cell, h = 18 } label
        ]
        |> Ui.group


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
