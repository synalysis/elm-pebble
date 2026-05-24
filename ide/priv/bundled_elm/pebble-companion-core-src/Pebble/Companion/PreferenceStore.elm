module Pebble.Companion.PreferenceStore exposing
    ( get
    , onPreference
    , set
    , setup
    )

{-| Generic phone-side preference storage exposed by the companion bridge.

# Commands

@docs get, set

# Subscriptions

@docs onPreference

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Read a preference value and deliver it to `toMsg`.
-}
get : String -> (Result String ( String, Decode.Value ) -> msg) -> Cmd msg
get key toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload ("preferences-get-" ++ key) "preferences" "get"
            (Encode.object [ ( "key", Encode.string key ) ])
            decodeResponse


{-| Store a preference value under a key.
-}
set : String -> Encode.Value -> Cmd msg
set key value =
    Phone.sendBridgeCommand <|
        (Command.command ("preferences-set-" ++ key) "preferences" "set"
            |> Command.withPayload
                (Encode.object
                    [ ( "key", Encode.string key )
                    , ( "value", value )
                    ]
                ))


{-| Receive pushed preference updates from the companion bridge.

Registering this subscription also tells the bridge to send preference updates.
-}
onPreference : (Result String ( String, Decode.Value ) -> msg) -> Sub msg
onPreference toMsg =
    Platform.subscribe (handler toMsg)


setup : Cmd msg
setup =
    Platform.setup preferencesInterest


{-| Platform router handler for preference events and responses.
-}
handler toMsg =
    Platform.handler preferencesInterest decodePreference toMsg


preferencesInterest =
    Platform.interest
        { id = "preferences"
        , subscribeCommand =
            Just <|
                Command.command "preferences-subscribe" "preferences" "subscribe"
        , eventPrefixes = [ "preferences." ]
        , resultIdPrefixes = [ "preferences-" ]
        }


decodeResponse : Decode.Value -> Result String ( String, Decode.Value )
decodeResponse value =
    decodePreference value


decodePreference : Decode.Value -> Result String ( String, Decode.Value )
decodePreference value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


decodeBridgeResult : Decode.Value -> Result String ( String, Decode.Value )
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Preference response missing payload"

                    Just payload ->
                        decodeValue payload

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String ( String, Decode.Value )
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "preferences.value" ->
            decodeValue bridgeEvent.payload

        "preferences.saved" ->
            decodeSavedKey bridgeEvent.payload

        "preferences.error" ->
            Err (decodeStringField "message" bridgeEvent.payload "Preferences unavailable")

        other ->
            Err ("Unexpected preferences event: " ++ other)


decodeSavedKey : Decode.Value -> Result String ( String, Decode.Value )
decodeSavedKey payload =
    Decode.decodeValue (Decode.field "key" Decode.string) payload
        |> Result.map (\key -> ( key, Encode.null ))
        |> Result.mapError Decode.errorToString


decodeValue : Decode.Value -> Result String ( String, Decode.Value )
decodeValue payload =
    Decode.decodeValue
        (Decode.map2 Tuple.pair
            (Decode.field "key" Decode.string)
            (Decode.field "value" Decode.value)
        )
        payload
        |> Result.mapError Decode.errorToString


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Preferences unavailable"


decodeStringField : String -> Decode.Value -> String -> String
decodeStringField field payload fallback =
    Decode.decodeValue (Decode.field field Decode.string) payload
        |> Result.withDefault fallback
