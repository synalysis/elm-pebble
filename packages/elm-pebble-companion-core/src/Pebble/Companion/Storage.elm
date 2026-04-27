module Pebble.Companion.Storage exposing
    ( Error(..)
    , Value(..)
    , clear
    , decodeGet
    , get
    , remove
    , set
    )

{-| Persistent key/value storage through the phone companion bridge.

    import Pebble.Companion.Storage as Storage

    saveHighScore =
        Storage.set "score-save" "high-score" (Storage.IntValue 9001)

# Values and errors
@docs Value, Error

# Commands
@docs set, get, remove, clear

# Results
@docs decodeGet

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeError, CommandEnvelope, ResultEnvelope)


{-| Values that can be stored by the companion bridge.
-}
type Value
    = StringValue String
    | IntValue Int
    | BoolValue Bool
    | JsonValue Encode.Value


{-| Storage result errors.
-}
type Error
    = BridgeFailure BridgeError
    | MissingPayload
    | DecodeFailure String


{-| Store a value under a key.
-}
set : String -> String -> Value -> CommandEnvelope
set id key value =
    Command.command id "storage" "set"
        |> Command.withPayload
            (Encode.object
                [ ( "key", Encode.string key )
                , ( "value", encodeValue value )
                ]
            )


{-| Request a value by key.
-}
get : String -> String -> CommandEnvelope
get id key =
    Command.command id "storage" "get"
        |> Command.withPayload (Encode.object [ ( "key", Encode.string key ) ])


{-| Remove a value by key.
-}
remove : String -> String -> CommandEnvelope
remove id key =
    Command.command id "storage" "remove"
        |> Command.withPayload (Encode.object [ ( "key", Encode.string key ) ])


{-| Remove all stored values.
-}
clear : String -> CommandEnvelope
clear id =
    Command.command id "storage" "clear"


{-| Decode the result of a `get` command.
-}
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
                    Ok value ->
                        Ok value

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
