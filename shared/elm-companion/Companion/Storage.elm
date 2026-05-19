module Companion.Storage exposing (Value(..), clear, get, onStorage, remove, set)

{-| Persistent companion storage helpers. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Storage as Storage


type Value
    = StringValue String
    | IntValue Int
    | BoolValue Bool
    | JsonValue Decode.Value


set : String -> Value -> Cmd msg
set key value =
    Storage.set ("storage-set-" ++ key) key (toCoreValue value)
        |> Phone.sendBridgeCommand


get : String -> Cmd msg
get key =
    Storage.get ("storage-get-" ++ key) key
        |> Phone.sendBridgeCommand


remove : String -> Cmd msg
remove key =
    Storage.remove ("storage-remove-" ++ key) key
        |> Phone.sendBridgeCommand


clear : Cmd msg
clear =
    Storage.clear "storage-clear"
        |> Phone.sendBridgeCommand


onStorage : (Result String Value -> msg) -> Sub msg
onStorage toMsg =
    Phone.onRawMessage (decodeStorage >> toMsg)


decodeStorage : Decode.Value -> Result String Value
decodeStorage value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok result ->
            case Storage.decodeGet result of
                Ok stored ->
                    Ok (fromCoreValue stored)

                Err _ ->
                    Err "Storage command failed"

        Err error ->
            Err (Decode.errorToString error)


toCoreValue : Value -> Storage.Value
toCoreValue value =
    case value of
        StringValue text ->
            Storage.StringValue text

        IntValue number ->
            Storage.IntValue number

        BoolValue flag ->
            Storage.BoolValue flag

        JsonValue json ->
            Storage.JsonValue json


fromCoreValue : Storage.Value -> Value
fromCoreValue value =
    case value of
        Storage.StringValue text ->
            StringValue text

        Storage.IntValue number ->
            IntValue number

        Storage.BoolValue flag ->
            BoolValue flag

        Storage.JsonValue json ->
            JsonValue json
