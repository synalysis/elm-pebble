module Companion.Environment exposing (EnvironmentInfo, MoonInfo, SunInfo, TideInfo, current, onEnvironment, subscribe)

{-| Sun, moon, and tide environment helpers for companion apps. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Environment as Environment


type alias SunInfo =
    Environment.SunInfo


type alias MoonInfo =
    Environment.MoonInfo


type alias TideInfo =
    Environment.TideInfo


type alias EnvironmentInfo =
    Environment.EnvironmentInfo


current : Cmd msg
current =
    Environment.current "environment-current"
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Environment.subscribe "environment-subscribe"
        |> Phone.sendBridgeCommand


onEnvironment : (Result String EnvironmentInfo -> msg) -> Sub msg
onEnvironment toMsg =
    Phone.onRawMessage (decodeEnvironment >> toMsg)


decodeEnvironment : Decode.Value -> Result String EnvironmentInfo
decodeEnvironment value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Environment.decode event of
                Environment.Current info ->
                    Ok info

                Environment.Error error ->
                    Err error

                Environment.Unknown eventName ->
                    Err ("Unexpected environment event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
