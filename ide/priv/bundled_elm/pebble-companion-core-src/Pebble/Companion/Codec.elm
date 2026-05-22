module Pebble.Companion.Codec exposing (decodeBridgeError, decodeEvent, decodeResult, encodeCommand)

{-| JSON codecs for bridge command, result, and event envelopes.

Use these decoders at the boundary where JavaScript bridge messages enter Elm.

# Encoding
@docs encodeCommand

# Decoding
@docs decodeBridgeError, decodeResult, decodeEvent

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Pebble.Companion.Contract exposing (BridgeError, BridgeEvent, CommandEnvelope, ResultEnvelope)


{-| Encode a command envelope into wire JSON.
-}
encodeCommand : CommandEnvelope -> Encode.Value
encodeCommand envelope =
    Encode.object
        [ ( "id", Encode.string envelope.id )
        , ( "api", Encode.string envelope.api )
        , ( "op", Encode.string envelope.op )
        , ( "payload", envelope.payload )
        ]


{-| Decode a bridge error envelope.
-}
decodeBridgeError : Decoder BridgeError
decodeBridgeError =
    Decode.map3 BridgeError
        (Decode.field "type" Decode.string)
        (Decode.field "message" Decode.string)
        (Decode.maybe (Decode.field "retryable" Decode.bool))


{-| Decode a result envelope.
-}
decodeResult : Decoder ResultEnvelope
decodeResult =
    Decode.map4 ResultEnvelope
        (Decode.field "id" Decode.string)
        (Decode.field "ok" Decode.bool)
        (Decode.maybe (Decode.field "payload" Decode.value))
        (Decode.maybe (Decode.field "error" decodeBridgeError))


{-| Decode a pushed bridge event.
-}
decodeEvent : Decoder BridgeEvent
decodeEvent =
    Decode.map2 BridgeEvent
        (Decode.field "event" Decode.string)
        (Decode.field "payload" Decode.value)
