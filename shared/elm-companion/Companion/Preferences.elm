module Companion.Preferences exposing (get, onPreference, set, subscribe)

{-| Generic phone-side preference helpers for companion apps. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Preferences as Preferences


get : String -> Cmd msg
get key =
    Preferences.get ("preferences-get-" ++ key) key
        |> Phone.sendBridgeCommand


set : String -> Encode.Value -> Cmd msg
set key value =
    Preferences.set ("preferences-set-" ++ key) key value
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Preferences.subscribe "preferences-subscribe"
        |> Phone.sendBridgeCommand


onPreference : (Result String ( String, Decode.Value ) -> msg) -> Sub msg
onPreference toMsg =
    Phone.onRawMessage (decodePreference >> toMsg)


decodePreference : Decode.Value -> Result String ( String, Decode.Value )
decodePreference value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Preferences.decode event of
                Preferences.Value key storedValue ->
                    Ok ( key, storedValue )

                Preferences.Saved key ->
                    Ok ( key, Encode.object [] )

                Preferences.Error error ->
                    Err error

                Preferences.Unknown eventName ->
                    Err ("Unexpected preferences event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
