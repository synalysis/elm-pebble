module Pebble.Companion.Geolocation exposing
    ( Event(..)
    , clearWatch
    , decode
    , getCurrentPosition
    , watch
    )

{-| Access browser geolocation through the phone companion bridge.

    Pebble.Companion.Geolocation.getCurrentPosition "location-now"

# Events
@docs Event, decode

# Commands
@docs getCurrentPosition, watch, clearWatch

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Geolocation events reported by the bridge.
-}
type Event
    = Position { latitude : Float, longitude : Float, accuracy : Float }
    | Error String
    | Unknown String


{-| Request the current phone location once.
-}
getCurrentPosition : String -> CommandEnvelope
getCurrentPosition id =
    Command.command id "geolocation" "getCurrentPosition"


{-| Start watching location changes.
-}
watch : String -> CommandEnvelope
watch id =
    Command.command id "geolocation" "watch"


{-| Stop a previously started location watch.
-}
clearWatch : String -> Int -> CommandEnvelope
clearWatch id watchId =
    Command.command id "geolocation" "clearWatch"
        |> Command.withPayload (Encode.object [ ( "watchId", Encode.int watchId ) ])


{-| Decode a bridge geolocation event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "geolocation.position" ->
            case Decode.decodeValue decodePosition bridgeEvent.payload of
                Ok payload ->
                    Position payload

                Err err ->
                    Error (Decode.errorToString err)

        "geolocation.error" ->
            Error
                (Decode.decodeValue (Decode.field "message" Decode.string) bridgeEvent.payload
                    |> Result.withDefault "Unknown geolocation error"
                )

        other ->
            Unknown other


decodePosition : Decode.Decoder { latitude : Float, longitude : Float, accuracy : Float }
decodePosition =
    Decode.map3 (\lat lon acc -> { latitude = lat, longitude = lon, accuracy = acc })
        (Decode.field "latitude" Decode.float)
        (Decode.field "longitude" Decode.float)
        (Decode.field "accuracy" Decode.float)
