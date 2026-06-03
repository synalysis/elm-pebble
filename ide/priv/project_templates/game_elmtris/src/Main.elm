module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Frame as Frame
import Pebble.Light as Light
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.Vibes as Vibes


boardCols : Int
boardCols =
    10


boardRows : Int
boardRows =
    14


boardSize : Int
boardSize =
    boardCols * boardRows


storageKey : Int
storageKey =
    8347


type alias Model =
    { board : List Int
    , pieceKind : Int
    , pieceRot : Int
    , pieceX : Int
    , pieceY : Int
    , pieceSlots : List Int
    , lockedSlots : List Int
    , score : Int
    , lines : Int
    , best : Int
    , seed : Int
    , tick : Int
    , dropEvery : Int
    , screenW : Int
    , screenH : Int
    , displayShape : Platform.DisplayShape
    , gameOver : Bool
    }


type alias ActivePiece =
    { kind : Int
    , rot : Int
    , x : Int
    , y : Int
    }


hasPiece : Model -> Bool
hasPiece model =
    model.pieceKind >= 0


activePiece : Model -> Maybe ActivePiece
activePiece model =
    if hasPiece model then
        Just
            { kind = model.pieceKind
            , rot = model.pieceRot
            , x = model.pieceX
            , y = model.pieceY
            }

    else
        Nothing


withPiece : Model -> Maybe ActivePiece -> Model
withPiece model piece =
    case piece of
        Nothing ->
            { model
                | pieceKind = -1
                , pieceRot = 0
                , pieceX = 0
                , pieceY = 0
                , pieceSlots = []
            }

        active ->
            { model
                | pieceKind = active.kind
                , pieceRot = active.rot
                , pieceX = active.x
                , pieceY = active.y
                , pieceSlots = pieceSlots active
            }


pieceSlots : ActivePiece -> List Int
pieceSlots piece =
    List.map
        (\( dx, dy ) ->
            (piece.y + dy) * boardCols + (piece.x + dx)
        )
        (pieceOffsets piece.kind piece.rot)


type Msg
    = FrameTick Frame.Frame
    | LeftPressed
    | RightPressed
    | UpPressed
    | DownPressed
    | BestLoaded String


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( freshModel 0 1 context.screen.width context.screen.height context.screen.shape
    , Cmd.batch
        [ Storage.readString storageKey BestLoaded
        , Light.enable
        ]
    )


freshModel : Int -> Int -> Int -> Int -> Platform.DisplayShape -> Model
freshModel best seed screenW screenH displayShape =
    let
        ( board, piece, nextSeed ) =
            spawnPiece emptyBoard seed

        model =
            withPiece
                { board = board
                , pieceKind = -1
                , pieceRot = 0
                , pieceX = 0
                , pieceY = 0
                , pieceSlots = []
                , lockedSlots = []
                , score = 0
                , lines = 0
                , best = best
                , seed = nextSeed
                , tick = 0
                , dropEvery = 28
                , screenW = screenW
                , screenH = screenH
                , displayShape = displayShape
                , gameOver = False
                }
                piece
    in
    { model | gameOver = model.pieceKind < 0 }


emptyBoard : List Int
emptyBoard =
    List.repeat boardSize 0


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FrameTick _ ->
            if model.gameOver then
                ( model, Cmd.none )

            else
                tickGravity model

        LeftPressed ->
            if model.gameOver then
                restart model

            else
                moveActive -1 0 model

        RightPressed ->
            if model.gameOver then
                ( model, Cmd.none )

            else
                moveActive 1 0 model

        UpPressed ->
            if model.gameOver then
                restart model

            else
                rotateActive model

        DownPressed ->
            if model.gameOver then
                ( model, Cmd.none )

            else
                softDrop model

        BestLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )


restart : Model -> ( Model, Cmd Msg )
restart model =
    let
        next =
            freshModel model.best (advanceSeed model.seed) model.screenW model.screenH model.displayShape
    in
    ( next, Cmd.none )


tickGravity : Model -> ( Model, Cmd Msg )
tickGravity model =
    let
        nextTick =
            model.tick + 1
    in
    if modBy model.dropEvery nextTick /= 0 then
        ( { model | tick = nextTick }, Cmd.none )

    else
        dropStep { model | tick = 0 }


dropStep : Model -> ( Model, Cmd Msg )
dropStep model =
    case activePiece model of
        Nothing ->
            ( model, Cmd.none )

        piece ->
            if canPlace piece.kind piece.rot piece.x (piece.y + 1) model.board then
                ( withPiece model (Just { piece | y = piece.y + 1 }), Cmd.none )

            else
                lockPiece model


softDrop : Model -> ( Model, Cmd Msg )
softDrop model =
    case activePiece model of
        Nothing ->
            ( model, Cmd.none )

        piece ->
            let
                nextY =
                    piece.y + 1
            in
            if canPlace piece.kind piece.rot piece.x nextY model.board then
                softDrop (withPiece model (Just { piece | y = nextY }))

            else
                ( model, Cmd.none )


moveActive : Int -> Int -> Model -> ( Model, Cmd Msg )
moveActive dx dy model =
    case activePiece model of
        Nothing ->
            ( model, Cmd.none )

        piece ->
            let
                nextX =
                    piece.x + dx

                nextY =
                    piece.y + dy
            in
            if canPlace piece.kind piece.rot nextX nextY model.board then
                ( withPiece model (Just { piece | x = nextX, y = nextY }), Cmd.none )

            else
                ( model, Cmd.none )


rotateActive : Model -> ( Model, Cmd Msg )
rotateActive model =
    case activePiece model of
        Nothing ->
            ( model, Cmd.none )

        piece ->
            let
                nextRot =
                    modBy 4 (piece.rot + 1)
            in
            if canPlace piece.kind nextRot piece.x piece.y model.board then
                ( withPiece model (Just { piece | rot = nextRot }), Cmd.none )

            else if canPlace piece.kind nextRot (piece.x - 1) piece.y model.board then
                ( withPiece model (Just { piece | rot = nextRot, x = piece.x - 1 }), Cmd.none )

            else if canPlace piece.kind nextRot (piece.x + 1) piece.y model.board then
                ( withPiece model (Just { piece | rot = nextRot, x = piece.x + 1 }), Cmd.none )

            else
                ( model, Cmd.none )


lockPiece : Model -> ( Model, Cmd Msg )
lockPiece model =
    case activePiece model of
        Nothing ->
            ( model, Cmd.none )

        piece ->
            let
                locked =
                    stampPiece piece model.board

                ( cleared, linesCleared ) =
                    clearLines locked

                nextScore =
                    model.score + lineScore linesCleared

                nextLines =
                    model.lines + linesCleared

                nextBest =
                    max model.best nextScore

                saveBest =
                    if nextBest > model.best then
                        Storage.writeString storageKey (String.fromInt nextBest)

                    else
                        Cmd.none

                ( nextBoard, nextPiece, nextSeed ) =
                    spawnPiece cleared (advanceSeed model.seed)

                nextDropEvery =
                    max 8 (model.dropEvery - linesCleared)

                gameOver =
                    nextPiece == Nothing
            in
            ( withPiece
                { model
                    | board = nextBoard
                    , lockedSlots = lockedSlotsFromBoard nextBoard
                    , seed = nextSeed
                    , score = nextScore
                    , lines = nextLines
                    , best = nextBest
                    , dropEvery = nextDropEvery
                    , gameOver = gameOver
                    , tick = 0
                }
                nextPiece
            , Cmd.batch
                [ saveBest
                , if linesCleared > 0 then
                      Vibes.shortPulse

                  else
                      Cmd.none
                ]
            )


lineScore : Int -> Int
lineScore count =
    case count of
        1 ->
            100

        2 ->
            300

        3 ->
            500

        _ ->
            800


spawnPiece : List Int -> Int -> ( List Int, Maybe ActivePiece, Int )
spawnPiece board seed =
    let
        nextSeed =
            advanceSeed seed

        kind =
            modBy 7 (randomIndex 7 seed)

        piece =
            { kind = kind, rot = 0, x = boardCols // 2 - 2, y = 0 }
    in
    if canPlace kind 0 piece.x piece.y board then
        ( board, Just piece, nextSeed )

    else
        ( board, Nothing, nextSeed )


canPlace : Int -> Int -> Int -> Int -> List Int -> Bool
canPlace kind rot x y board =
    List.all
        (\( dx, dy ) ->
            let
                cellX =
                    x + dx

                cellY =
                    y + dy
            in
            cellX >= 0
                && cellX < boardCols
                && cellY < boardRows
                && (cellY < 0 || cellAt cellX cellY board == 0)
        )
        (pieceOffsets kind rot)


stampPiece : ActivePiece -> List Int -> List Int
stampPiece piece board =
    List.foldl
        (\( dx, dy ) acc ->
            let
                value =
                    piece.kind + 1
            in
            setCell (piece.x + dx) (piece.y + dy) value acc
        )
        board
        (pieceOffsets piece.kind piece.rot)


clearLines : List Int -> ( List Int, Int )
clearLines board =
    let
        kept =
            List.range 0 (boardRows - 1)
                |> List.filterMap
                    (\row ->
                        if rowFull row board then
                            Nothing

                        else
                            Just (rowCells row board)
                    )

        cleared =
            boardRows - List.length kept
    in
    ( List.concat (List.repeat cleared (List.repeat boardCols 0) ++ kept)
    , cleared
    )


rowFull : Int -> List Int -> Bool
rowFull row board =
    List.all ((/=) 0) (rowCells row board)


rowCells : Int -> List Int -> List Int
rowCells row board =
    List.range 0 (boardCols - 1)
        |> List.map (\col -> cellAt col row board)


cellAt : Int -> Int -> List Int -> Int
cellAt x y board =
    Maybe.withDefault 0 (listAt (y * boardCols + x) board)


setCell : Int -> Int -> Int -> List Int -> List Int
setCell x y value board =
    if x < 0 || x >= boardCols || y < 0 || y >= boardRows then
        board

    else
        List.indexedMap
            (\index cell ->
                if index == y * boardCols + x then
                    value

                else
                    cell
            )
            board


listAt : Int -> List a -> Maybe a
listAt index values =
    if index < 0 then
        Nothing

    else
        List.head (List.drop index values)


pieceOffsets : Int -> Int -> List ( Int, Int )
pieceOffsets kind rot =
    case modBy 7 kind of
        0 ->
            case modBy 4 rot of
                0 ->
                    [ ( 0, 0 ), ( 1, 0 ), ( 2, 0 ), ( 3, 0 ) ]

                1 ->
                    [ ( 2, 0 ), ( 2, 1 ), ( 2, 2 ), ( 2, 3 ) ]

                2 ->
                    [ ( 0, 2 ), ( 1, 2 ), ( 2, 2 ), ( 3, 2 ) ]

                _ ->
                    [ ( 1, 0 ), ( 1, 1 ), ( 1, 2 ), ( 1, 3 ) ]

        1 ->
            [ ( 0, 0 ), ( 1, 0 ), ( 0, 1 ), ( 1, 1 ) ]

        2 ->
            case modBy 4 rot of
                0 ->
                    [ ( 1, 0 ), ( 0, 1 ), ( 1, 1 ), ( 2, 1 ) ]

                1 ->
                    [ ( 1, 0 ), ( 1, 1 ), ( 2, 1 ), ( 1, 2 ) ]

                2 ->
                    [ ( 0, 1 ), ( 1, 1 ), ( 2, 1 ), ( 1, 2 ) ]

                _ ->
                    [ ( 1, 0 ), ( 0, 1 ), ( 1, 1 ), ( 1, 2 ) ]

        3 ->
            case modBy 4 rot of
                0 ->
                    [ ( 1, 0 ), ( 2, 0 ), ( 0, 1 ), ( 1, 1 ) ]

                1 ->
                    [ ( 1, 0 ), ( 1, 1 ), ( 2, 1 ), ( 2, 2 ) ]

                2 ->
                    [ ( 1, 1 ), ( 2, 1 ), ( 0, 2 ), ( 1, 2 ) ]

                _ ->
                    [ ( 0, 0 ), ( 0, 1 ), ( 1, 1 ), ( 1, 2 ) ]

        4 ->
            case modBy 4 rot of
                0 ->
                    [ ( 0, 0 ), ( 1, 0 ), ( 1, 1 ), ( 2, 1 ) ]

                1 ->
                    [ ( 2, 0 ), ( 1, 1 ), ( 2, 1 ), ( 1, 2 ) ]

                2 ->
                    [ ( 0, 1 ), ( 1, 1 ), ( 2, 1 ), ( 1, 2 ) ]

                _ ->
                    [ ( 1, 0 ), ( 0, 1 ), ( 1, 1 ), ( 0, 2 ) ]

        5 ->
            case modBy 4 rot of
                0 ->
                    [ ( 0, 0 ), ( 0, 1 ), ( 1, 1 ), ( 2, 1 ) ]

                1 ->
                    [ ( 1, 0 ), ( 2, 0 ), ( 1, 1 ), ( 1, 2 ) ]

                2 ->
                    [ ( 0, 1 ), ( 1, 1 ), ( 2, 1 ), ( 2, 2 ) ]

                _ ->
                    [ ( 1, 0 ), ( 1, 1 ), ( 0, 2 ), ( 1, 2 ) ]

        _ ->
            case modBy 4 rot of
                0 ->
                    [ ( 2, 0 ), ( 0, 1 ), ( 1, 1 ), ( 2, 1 ) ]

                1 ->
                    [ ( 1, 0 ), ( 1, 1 ), ( 1, 2 ), ( 2, 2 ) ]

                2 ->
                    [ ( 0, 1 ), ( 1, 1 ), ( 2, 1 ), ( 0, 2 ) ]

                _ ->
                    [ ( 0, 0 ), ( 1, 0 ), ( 1, 1 ), ( 1, 2 ) ]


advanceSeed : Int -> Int
advanceSeed seed =
    modBy 2147483647 (seed * 16807 + 11)


randomIndex : Int -> Int -> Int
randomIndex maxExclusive seed =
    if maxExclusive <= 0 then
        0

    else
        modBy maxExclusive seed


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Frame.every 33 FrameTick
        , Button.onPress Button.Back LeftPressed
        , Button.onPress Button.Select RightPressed
        , Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    let
        layout =
            boardLayout model

        overlay =
            if model.gameOver then
                gameOverOps model

            else
                []
    in
    Ui.toUiNode
        ([ Ui.clear Color.white ]
            ++ hudOps model
            ++ lockedSlotOps layout model
            ++ pieceSlotOps layout model
            ++ overlay
        )


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

            gap =
                1

            cell =
                max 4 ((diameter * 2 // 3 - gap * (boardCols - 1)) // boardCols)

            boardW =
                cell * boardCols + gap * (boardCols - 1)

        in
        { x = (model.screenW - boardW) // 2
        , y = (model.screenH - boardW) // 2 + 8
        , cell = cell
        , gap = gap
        , pieceKind = model.pieceKind
        }

    else
        let
            top =
                30

            sideMargin =
                6

            bottomMargin =
                4

            gap =
                1

            maxBoardW =
                model.screenW - sideMargin * 2

            maxBoardH =
                model.screenH - top - bottomMargin

            cellW =
                (maxBoardW - gap * (boardCols - 1)) // boardCols

            cellH =
                (maxBoardH - gap * (boardRows - 1)) // boardRows

            cell =
                max 4 (min cellW cellH)

            boardW =
                cell * boardCols + gap * (boardCols - 1)
        in
        { x = (model.screenW - boardW) // 2
        , y = top
        , cell = cell
        , gap = gap
        }


lockedSlotsFromBoard : List Int -> List Int
lockedSlotsFromBoard board =
    List.foldl
        (\index slots ->
            if cellAt (modBy boardCols index) (index // boardCols) board == 0 then
                slots

            else
                index :: slots
        )
        []
        (List.range 0 (boardSize - 1))
        |> List.reverse


lockedSlotOps : BoardLayout -> Model -> List Ui.RenderOp
lockedSlotOps layout model =
    List.map
        (\slot ->
            drawAt layout (modBy boardCols slot) (slot // boardCols) (cellAt (modBy boardCols slot) (slot // boardCols) model.board)
        )
        model.lockedSlots


pieceSlotOps : BoardLayout -> Model -> List Ui.RenderOp
pieceSlotOps layout model =
    List.map
        (\slot ->
            drawAt layout (modBy boardCols slot) (slot // boardCols) (model.pieceKind + 1)
        )
        model.pieceSlots


drawAt : BoardLayout -> Int -> Int -> Int -> Ui.RenderOp
drawAt layout col row kind =
    let
        x =
            layout.x + col * (layout.cell + layout.gap)

        y =
            layout.y + row * (layout.cell + layout.gap)
    in
    Ui.fillRect { x = x, y = y, w = layout.cell, h = layout.cell }
        (if kind == 0 then
            Color.white

         else
            cellColor kind
        )


cellColor : Int -> Color
cellColor kind =
    case modBy 7 (kind - 1) of
        0 ->
            Color.black

        1 ->
            Color.darkGray

        2 ->
            Color.black

        3 ->
            Color.darkGray

        4 ->
            Color.black

        5 ->
            Color.darkGray

        _ ->
            Color.black


hudOps : Model -> List Ui.RenderOp
hudOps model =
    let
        textOptions =
            if Platform.displayShapeIsRound model.displayShape then
                Ui.alignCenter Ui.defaultTextOptions

            else
                Ui.defaultTextOptions

        textW =
            if Platform.displayShapeIsRound model.displayShape then
                (min model.screenW model.screenH * 4) // 9

            else
                model.screenW - 8

        textX =
            (model.screenW - textW) // 2

        y =
            if Platform.displayShapeIsRound model.displayShape then
                6

            else
                4
    in
    [ Ui.text Resources.DefaultFont textOptions { x = textX, y = y, w = textW, h = 14 } "Elmtris"
    , Ui.textInt Resources.DefaultFont { x = textX, y = y + 14 } model.score
    , Ui.textInt Resources.DefaultFont { x = textX + textW // 2, y = y + 14 } model.lines
    ]


gameOverOps : Model -> List Ui.RenderOp
gameOverOps model =
    let
        textOptions =
            Ui.alignCenter Ui.defaultTextOptions

        textW =
            if Platform.displayShapeIsRound model.displayShape then
                (min model.screenW model.screenH * 4) // 9

            else
                model.screenW - 8

        textX =
            (model.screenW - textW) // 2

        textY =
            if Platform.displayShapeIsRound model.displayShape then
                (model.screenH // 2) - 14

            else
                model.screenH - 28
    in
    [ Ui.text Resources.DefaultFont textOptions { x = textX, y = textY, w = textW, h = 28 } "Up/Back" ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
