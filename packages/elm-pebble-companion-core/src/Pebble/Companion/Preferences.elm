module Pebble.Companion.Preferences exposing (Event(..), decode, get, set, subscribe)

{-| Generic persistent user preferences exposed by the companion bridge.

App-specific generated configuration remains in `GeneratedPreferences`; this
module is for bridge-managed phone-side preference values.

# Events
@docs Event, decode

# Commands
@docs get, set, subscribe

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Preference events emitted by the companion bridge.
-}
type Event
    = Value String Decode.Value
    | Saved String
    | Error String
    | Unknown String


{-| Request a preference value by key.
-}
get : String -> String -> CommandEnvelope
get id key =
    Command.command id "preferences" "get"
        |> Command.withPayload (Encode.object [ ( "key", Encode.string key ) ])


{-| Save a preference value by key.
-}
set : String -> String -> Encode.Value -> CommandEnvelope
set id key value =
    Command.command id "preferences" "set"
        |> Command.withPayload
            (Encode.object
                [ ( "key", Encode.string key )
                , ( "value", value )
                ]
            )


{-| Subscribe to preference changes when supported.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "preferences" "subscribe"


{-| Decode a pushed preference bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "preferences.value" ->
            case Decode.decodeValue decodeValue bridgeEvent.payload of
                Ok ( key, value ) ->
                    Value key value

                Err error ->
                    Error (Decode.errorToString error)

        "preferences.saved" ->
            Saved (decodeStringField "key" bridgeEvent.payload "")

        "preferences.error" ->
            Error (decodeStringField "message" bridgeEvent.payload "Preferences unavailable")

        other ->
            Unknown other


decodeValue : Decode.Decoder ( String, Decode.Value )
decodeValue =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.field "value" Decode.value)


decodeStringField : String -> Decode.Value -> String -> String
decodeStringField field payload fallback =
    Decode.decodeValue (Decode.field field Decode.string) payload
        |> Result.withDefault fallback
