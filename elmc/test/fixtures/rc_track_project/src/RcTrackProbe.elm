module RcTrackProbe exposing (branchTupleOut, concatRows, foldSum, stringAppendLength)

import List
import Maybe
import Result
import String
import Tuple


foldSum : List Int -> Int
foldSum items =
    List.foldl (+) 0 items


concatRows : List (List Int) -> List Int
concatRows rows =
    List.concat rows


branchTupleOut : ( Result String Int, Maybe Int ) -> ( Int, Int )
branchTupleOut pair =
    case pair of
        ( Ok value, maybeNumber ) ->
            ( value, Maybe.withDefault 0 maybeNumber )


stringAppendLength : String -> String -> Int
stringAppendLength left right =
    String.length (left ++ right)
