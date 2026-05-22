module Pebble.Storage exposing (writeInt, readInt, writeString, readString, delete)

{-| Watch-local key/value storage commands.

The watch runtime exposes a lightweight integer key/value store.

    saveCounter : Cmd msg
    saveCounter =
        writeInt 1 42

    loadCounter : Cmd Msg
    loadCounter =
        readInt 1 CounterLoaded


# Operations

@docs writeInt, readInt, writeString, readString, delete

-}

import Elm.Kernel.PebbleWatch


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


{-| Store a string value under an integer key.
-}
writeString : Int -> String -> Cmd msg
writeString =
    Elm.Kernel.PebbleWatch.storageWriteString


{-| Read a string by key and send it to `toMsg`.
-}
readString : Int -> (String -> msg) -> Cmd msg
readString =
    Elm.Kernel.PebbleWatch.storageReadString


{-| Remove a stored value at `key`.
-}
delete : Int -> Cmd msg
delete =
    Elm.Kernel.PebbleWatch.storageDelete
