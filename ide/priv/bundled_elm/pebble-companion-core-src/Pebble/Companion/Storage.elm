module Pebble.Companion.Storage exposing
    ( Error(..)
    , Value(..)
    , clear
    , get
    , onStorage
    , remove
    , set
    , setup
    )

{-| Persistent companion storage helpers.

# Values and errors

@docs Value, Error

# Commands

@docs set, get, remove, clear, setup

# Subscriptions

@docs onStorage

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeError, ResultEnvelope)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| A stored companion value.
-}
type Value
    = StringValue String
    | IntValue Int
    | BoolValue Bool
    | JsonValue Encode.Value


{-| Errors reported while reading companion storage.
-}
type Error
    = BridgeFailure BridgeError
    | MissingPayload
    | DecodeFailure String


{-| Store a value under a key.
-}
set : String -> Value -> Cmd msg
set key value =
    Phone.sendBridgeCommand <|
        (Command.command ("storage-set-" ++ key) "storage" "set"
            |> Command.withPayload
                (Encode.object
                    [ ( "key", Encode.string key )
                    , ( "value", encodeValue value )
                    ]
                )
        )


{-| Read a stored value and deliver it to `toMsg`.
-}
get : String -> (Result Error Value -> msg) -> Cmd msg
get key toMsg =
    Phone.send (Result.mapError DecodeFailure >> toMsg) <|
        Phone.requestWithPayload ("storage-get-" ++ key) "storage" "get"
            (Encode.object [ ( "key", Encode.string key ) ])
            (decodeGetResponse >> Result.mapError errorToString)


errorToString : Error -> String
errorToString error =
    case error of
        BridgeFailure bridgeError ->
            bridgeError.message

        MissingPayload ->
            "Storage response missing payload"

        DecodeFailure message ->
            message


{-| Remove a stored key.
-}
remove : String -> Cmd msg
remove key =
    Phone.sendBridgeCommand <|
        (Command.command ("storage-remove-" ++ key) "storage" "remove"
            |> Command.withPayload (Encode.object [ ( "key", Encode.string key ) ])
        )


{-| Clear all stored values.
-}
clear : Cmd msg
clear =
    Phone.sendBridgeCommand <|
        Command.command "storage-clear" "storage" "clear"


{-| Receive storage command responses routed through the platform bridge.
-}
onStorage : (Result Error Value -> msg) -> Sub msg
onStorage toMsg =
    Platform.subscribe (handler toMsg)


{-| Register the storage platform handler with the companion bridge.
-}
setup : Cmd msg
setup =
    Platform.setup storageInterest


{-| Platform router handler for storage command responses.
-}
handler toMsg =
    Platform.handler storageInterest
        (decodeStorage >> Result.mapError errorToString)
        (Result.mapError DecodeFailure >> toMsg)


storageInterest =
    Platform.interest
        { id = "storage"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "storage-" ]
        }


decodeGetResponse : Decode.Value -> Result Error Value
decodeGetResponse value =
    decodeStorage value


decodeStorage : Decode.Value -> Result Error Value
decodeStorage value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            decodeGet envelope

        Err error ->
            Err (DecodeFailure (Decode.errorToString error))


decodeGet : ResultEnvelope -> Result Error Value
decodeGet envelope =
    if not envelope.ok then
        case envelope.error of
            Just bridgeError ->
                Err (BridgeFailure bridgeError)

            Nothing ->
                Err MissingPayload

    else
        case envelope.payload of
            Nothing ->
                Err MissingPayload

            Just payload ->
                case Decode.decodeValue decodeValue payload of
                    Ok stored ->
                        Ok stored

                    Err err ->
                        Err (DecodeFailure (Decode.errorToString err))


encodeValue : Value -> Encode.Value
encodeValue value =
    case value of
        StringValue text ->
            Encode.object
                [ ( "kind", Encode.string "string" )
                , ( "value", Encode.string text )
                ]

        IntValue number ->
            Encode.object
                [ ( "kind", Encode.string "int" )
                , ( "value", Encode.int number )
                ]

        BoolValue flag ->
            Encode.object
                [ ( "kind", Encode.string "bool" )
                , ( "value", Encode.bool flag )
                ]

        JsonValue json ->
            Encode.object
                [ ( "kind", Encode.string "json" )
                , ( "value", json )
                ]


decodeValue : Decode.Decoder Value
decodeValue =
    Decode.field "kind" Decode.string
        |> Decode.andThen
            (\kind ->
                case kind of
                    "string" ->
                        Decode.map StringValue (Decode.field "value" Decode.string)

                    "int" ->
                        Decode.map IntValue (Decode.field "value" Decode.int)

                    "bool" ->
                        Decode.map BoolValue (Decode.field "value" Decode.bool)

                    "json" ->
                        Decode.map JsonValue (Decode.field "value" Decode.value)

                    _ ->
                        Decode.fail ("Unknown storage value kind: " ++ kind)
            )
