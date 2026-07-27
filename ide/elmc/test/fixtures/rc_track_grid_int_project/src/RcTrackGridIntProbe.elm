module RcTrackGridIntProbe exposing (probeGridAccess, probeGridUpdate)


emptyGrid : List Int
emptyGrid =
    List.repeat 16 0


listAt : Int -> List Int -> Maybe Int
listAt index cells =
    List.head (List.drop index cells)


cellAt : Int -> Int -> List Int -> Int
cellAt x y cells =
    if y < 0 || y >= 4 || x < 0 || x >= 4 then
        0

    else
        Maybe.withDefault 0 (listAt (y * 4 + x) cells)


setAt : Int -> Int -> List Int -> List Int
setAt index value cells =
    List.indexedMap
        (\i current ->
            if i == index then
                value

            else
                current
        )
        cells


probeGridAccess : Int
probeGridAccess =
    cellAt 2 1 [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 ]


probeGridUpdate : Int
probeGridUpdate =
    let
        cells =
            emptyGrid
                |> setAt 5 8
                |> setAt 10 13
    in
    cellAt 1 1 cells + cellAt 2 2 cells
