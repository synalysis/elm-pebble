module Pebble.Storage exposing (delete, readInt, writeInt)

import Elm.Kernel.PebbleWatch


writeInt : Int -> Int -> Cmd msg
writeInt =
    Elm.Kernel.PebbleWatch.storageWriteInt


readInt : Int -> (Int -> msg) -> Cmd msg
readInt =
    Elm.Kernel.PebbleWatch.storageReadInt


delete : Int -> Cmd msg
delete =
    Elm.Kernel.PebbleWatch.storageDelete
