module CaseSubject exposing (decodeFromDict, parseField)

import Dict exposing (Dict)
import String


decodeFromDict : String -> Dict String Int -> Int
decodeFromDict key dict =
    case Dict.get key dict of
        Just value ->
            value

        Nothing ->
            0


parseField : { value : String } -> Int
parseField record =
    case String.toInt record.value of
        Just number ->
            number

        Nothing ->
            0
