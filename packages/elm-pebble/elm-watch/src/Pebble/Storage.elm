module Pebble.Storage exposing (writeInt, readInt, writeString, readString, delete, maxSize)

{-| Watch-local key/value storage commands.

The watch runtime exposes a lightweight integer- and string-keyed store.
Keys are integers; values can be ints or strings. Use `maxSize` to learn the
per-app byte limit on the current firmware.

    import Pebble.Storage as Storage

    storageKey : Int
    storageKey =
        1

    type Msg
        = CounterLoaded Int
        | MaxSizeLoaded Int

    init _ =
        ( model
        , Cmd.batch
            [ Storage.readInt storageKey CounterLoaded
            , Storage.maxSize MaxSizeLoaded
            ]
        )

    saveCounter : Int -> Cmd msg
    saveCounter value =
        Storage.writeInt storageKey value

For a runnable example, use the **watch-demo-storage** project template in the IDE.

# Operations

@docs writeInt, readInt, writeString, readString, delete, maxSize

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


{-| Query the per-app persistent storage byte limit on this firmware.
-}
maxSize : (Int -> msg) -> Cmd msg
maxSize =
    Elm.Kernel.PebbleWatch.storageReadMaxSize
