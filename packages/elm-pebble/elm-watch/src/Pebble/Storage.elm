module Pebble.Storage exposing (delete, readInt, writeInt)

import Elm.Kernel.PebbleWatch

{-| Watch-local integer key/value storage commands.

The watch runtime exposes a lightweight integer key/value store.

    saveCounter : Cmd msg
    saveCounter =
        writeInt 1 42

    loadCounter : Cmd Msg
    loadCounter =
        readInt 1 CounterLoaded

# Operations
@docs writeInt, readInt, delete

-}


{-| Store an integer value under an integer key.
-}
writeInt : Int -> Int -> Cmd msg
writeInt =
    Elm.Kernel.PebbleWatch.storageWriteInt


{-| Read an integer by key and send it to `toMsg`.
-}
readInt : Int -> (Int -> msg) -> Cmd msg
readInt =
    Elm.Kernel.PebbleWatch.storageReadInt


{-| Remove a stored value at `key`.
-}
delete : Int -> Cmd msg
delete =
    Elm.Kernel.PebbleWatch.storageDelete
