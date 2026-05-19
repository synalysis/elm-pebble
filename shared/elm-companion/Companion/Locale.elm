module Companion.Locale exposing (LocaleInfo, current, onLocale, subscribe)

{-| Phone locale and regional preference helpers. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Locale as Locale


type alias LocaleInfo =
    Locale.LocaleInfo


current : Cmd msg
current =
    Locale.status "locale-status"
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Locale.subscribe "locale-subscribe"
        |> Phone.sendBridgeCommand


onLocale : (Result String LocaleInfo -> msg) -> Sub msg
onLocale toMsg =
    Phone.onRawMessage (decodeLocale >> toMsg)


decodeLocale : Decode.Value -> Result String LocaleInfo
decodeLocale value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Locale.decode event of
                Locale.Status info ->
                    Ok info

                Locale.Error error ->
                    Err error

                Locale.Unknown eventName ->
                    Err ("Unexpected locale event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
