port module Companion.Geolocation exposing (Location, currentPosition, onCurrentPosition)

{-| Companion-side geolocation helpers.

This wraps the lower-level bridge command/event API so companion apps can request
the current phone location with a `Cmd` and receive the result in `update`.
-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Geolocation as Geolocation


type alias Location =
    { latitude : Float
    , longitude : Float
    , accuracy : Float
    }


port geolocationOutgoing : Encode.Value -> Cmd msg


port geolocationIncoming : (Decode.Value -> msg) -> Sub msg


currentPosition : Cmd msg
currentPosition =
    Geolocation.getCurrentPosition "current-position"
        |> Codec.encodeCommand
        |> geolocationOutgoing


onCurrentPosition : (Result String Location -> msg) -> Sub msg
onCurrentPosition toMsg =
    geolocationIncoming (decodeGeolocation >> toMsg)


decodeGeolocation : Decode.Value -> Result String Location
decodeGeolocation value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Geolocation.decode event of
                Geolocation.Position location ->
                    Ok
                        { latitude = location.latitude
                        , longitude = location.longitude
                        , accuracy = location.accuracy
                        }

                Geolocation.Error error ->
                    Err error

                Geolocation.Unknown eventName ->
                    Err ("Unexpected geolocation event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
