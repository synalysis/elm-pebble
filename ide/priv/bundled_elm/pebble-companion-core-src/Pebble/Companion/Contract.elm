module Pebble.Companion.Contract exposing (BridgeError, BridgeEvent, CommandEnvelope, ResultEnvelope)

{-| Shared data contracts for the Pebble companion bridge.

These records describe the JSON envelopes exchanged between Elm and the
JavaScript bridge.

# Envelopes
@docs CommandEnvelope, ResultEnvelope, BridgeError, BridgeEvent

-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| Structured command envelope sent from Elm to the JS companion bridge.
-}
type alias CommandEnvelope =
    { id : String
    , api : String
    , op : String
    , payload : Encode.Value
    }


{-| Structured result envelope sent from JS companion bridge back to Elm.
-}
type alias ResultEnvelope =
    { id : String
    , ok : Bool
    , payload : Maybe Decode.Value
    , error : Maybe BridgeError
    }


{-| Structured bridge errors instead of plain string errors.
-}
type alias BridgeError =
    { type_ : String
    , message : String
    , retryable : Maybe Bool
    }


{-| Pushed event envelope from JS companion bridge to Elm.
-}
type alias BridgeEvent =
    { event : String
    , payload : Decode.Value
    }
