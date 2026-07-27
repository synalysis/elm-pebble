module Main exposing (main)

import Json.Decode as Decode
import Pebble.Cmd as PebbleCmd
import Pebble.Events as Events
import Pebble.Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias GridModel =
    { cells : List Int
    , seed : Int
    , score : Int
    , best : Int
    , turn : Int
    }


type Dir
    = Left
    | Right
    | Up
    | Down


type Msg
    = GoLeft
    | GoRight
    | GoUp
    | GoDown


type alias LineResult =
    { cells : List Int
    , score : Int
    }


sliceRow : Int -> List Int -> List Int
sliceRow row board =
    List.take 3 (List.drop (row * 3) board)


slideMerge : List Int -> LineResult
slideMerge values =
    case values of
        a :: b :: rest ->
            if a == b then
                let
                    tail =
                        slideMerge rest

                    value =
                        a + b
                in
                { cells = value :: tail.cells, score = value + tail.score }

            else
                let
                    tail =
                        slideMerge (b :: rest)
                in
                { cells = a :: tail.cells, score = tail.score }

        _ ->
            { cells = values, score = 0 }


slideLine : List Int -> LineResult
slideLine row =
    let
        merged =
            slideMerge (List.filter ((/=) 0) row)
    in
    { cells = merged.cells ++ List.repeat (3 - List.length merged.cells) 0
    , score = merged.score
    }


collapseGrid : List Int -> LineResult
collapseGrid cells =
    let
        row0 =
            slideLine (sliceRow 0 cells)

        row1 =
            slideLine (sliceRow 1 cells)

        row2 =
            slideLine (sliceRow 2 cells)
    in
    { cells = row0.cells ++ row1.cells ++ row2.cells
    , score = row0.score + row1.score + row2.score
    }


flipRows : List Int -> List Int
flipRows cells =
    List.concat
        [ List.reverse (sliceRow 0 cells)
        , List.reverse (sliceRow 1 cells)
        , List.reverse (sliceRow 2 cells)
        ]


fetchAt : Int -> List Int -> Maybe Int
fetchAt index values =
    if index < 0 then
        Nothing
    else
        List.head (List.drop index values)


swapAxes : List Int -> List Int
swapAxes cells =
    List.map
        (\i -> Maybe.withDefault 0 (fetchAt i cells))
        [ 0, 3, 6, 1, 4, 7, 2, 5, 8 ]


faceGrid : Dir -> List Int -> List Int
faceGrid direction cells =
    case direction of
        Left ->
            cells

        Right ->
            flipRows cells

        Up ->
            swapAxes cells

        Down ->
            flipRows (swapAxes cells)


unfaceGrid : Dir -> List Int -> List Int
unfaceGrid direction cells =
    case direction of
        Left ->
            cells

        Right ->
            flipRows cells

        Up ->
            swapAxes cells

        Down ->
            swapAxes (flipRows cells)


addTile : Int -> List Int -> ( List Int, Int )
addTile seed cells =
    ( cells, seed + 1 )


slideGrid : Dir -> GridModel -> ( GridModel, Cmd msg )
slideGrid direction model =
    let
        faced =
            faceGrid direction model.cells

        squashed =
            collapseGrid faced

        restored =
            unfaceGrid direction squashed.cells
    in
    if restored == model.cells then
        ( model, PebbleCmd.none )

    else
        let
            ( nextCells, nextSeed ) =
                addTile model.seed restored

            nextScore =
                model.score + squashed.score

            nextBest =
                max model.best nextScore

            saveCmd =
                if nextBest > model.best then
                    Storage.writeString 99 (String.fromInt nextBest)

                else
                    PebbleCmd.none
        in
        ( { model
            | cells = nextCells
            , seed = nextSeed
            , score = nextScore
            , best = nextBest
            , turn = model.turn + 1
          }
        , saveCmd
        )


init _ =
    ( { cells = [ 2, 2, 0, 0, 0, 0, 0, 0, 0 ]
      , seed = 1
      , score = 0
      , best = 0
      , turn = 0
      }
    , PebbleCmd.none
    )


update msg model =
    case msg of
        GoLeft ->
            slideGrid Left model

        GoRight ->
            slideGrid Right model

        GoUp ->
            slideGrid Up model

        GoDown ->
            slideGrid Down model


view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.textInt Resources.DefaultFont { x = 0, y = 0 } model.turn
        ]


subscriptions _ =
    Events.batch []


main =
    Pebble.Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
