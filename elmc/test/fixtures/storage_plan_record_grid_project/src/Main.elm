module Main exposing (main)

import Array


type alias Cell =
    { row : Int
    , col : Int
    }


grid : List Cell
grid =
    [ { row = 0, col = 0 }
    , { row = 1, col = 1 }
    , { row = 2, col = 0 }
    ]


sumRows : List Cell -> Int
sumRows cells =
    case cells of
        [] ->
            0

        cell :: rest ->
            cell.row + sumRows rest


sumGrid : Int
sumGrid =
    sumRows grid


main : Int
main =
    sumGrid
