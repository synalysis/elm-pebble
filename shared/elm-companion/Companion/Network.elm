module Companion.Network exposing (current, onNetwork, subscribe)

{-| Phone network status helpers. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Network as Network


current : Cmd msg
current =
    Network.status "network-status"
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Network.subscribe "network-subscribe"
        |> Phone.sendBridgeCommand


onNetwork : (Result String Bool -> msg) -> Sub msg
onNetwork toMsg =
    Phone.onRawMessage (decodeNetwork >> toMsg)


decodeNetwork : Decode.Value -> Result String Bool
decodeNetwork value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Network.decode event of
                Network.StatusChanged online ->
                    Ok online

                Network.Unknown eventName ->
                    Err ("Unexpected network event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
