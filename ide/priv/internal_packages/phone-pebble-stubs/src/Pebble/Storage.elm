module Pebble.Storage exposing (delete, readInt, readString, writeInt, writeString)


writeInt : Int -> Int -> Cmd msg
writeInt _ _ =
    Cmd.none


readInt : Int -> (Int -> msg) -> Cmd msg
readInt _ _ =
    Cmd.none


writeString : Int -> String -> Cmd msg
writeString _ _ =
    Cmd.none


readString : Int -> (String -> msg) -> Cmd msg
readString _ _ =
    Cmd.none


delete : Int -> Cmd msg
delete _ =
    Cmd.none
