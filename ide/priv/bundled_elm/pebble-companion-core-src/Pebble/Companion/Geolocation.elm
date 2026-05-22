port module Pebble.Companion.Geolocation exposing
    ( Location
    , currentPosition
    , onCurrentPosition
    )

{-| Companion-side geolocation helpers.

    init _ =
        ( model, Geolocation.currentPosition GotLocation )

# Types

@docs Location

# Commands

@docs currentPosition

# Subscriptions

@docs onCurrentPosition

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone


{-| A latitude, longitude, and accuracy reading.
-}
type alias Location =
    { latitude : Float
    , longitude : Float
    , accuracy : Float
    }


port geolocationOutgoing : Encode.Value -> Cmd msg


port geolocationIncoming : (Decode.Value -> msg) -> Sub msg


{-| Request the current device position and deliver it to `toMsg`.
-}
currentPosition : (Result String Location -> msg) -> Cmd msg
currentPosition toMsg =
    Cmd.batch
        [ registerGeolocationHandler toMsg
        , Command.command "current-position" "geolocation" "getCurrentPosition"
            |> Codec.encodeCommand
            |> geolocationOutgoing
        ]


{-| Receive pushed geolocation updates from the companion bridge.
-}
onCurrentPosition : (Result String Location -> msg) -> Sub msg
onCurrentPosition toMsg =
    geolocationIncoming (decodeGeolocation >> toMsg)


registerGeolocationHandler : (Result String Location -> msg) -> Cmd msg
registerGeolocationHandler toMsg =
    let
        _ =
            toMsg
    in
    Phone.sendBridgeCommand <|
        Command.command "geolocation-register" "geolocation" "register"
            |> Command.withPayload (Encode.object [ ( "id", Encode.string "current-position" ) ])


decodeGeolocation : Decode.Value -> Result String Location
decodeGeolocation value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String Location
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "geolocation.position" ->
            Decode.decodeValue decodePosition bridgeEvent.payload
                |> Result.map
                    (\location ->
                        { latitude = location.latitude
                        , longitude = location.longitude
                        , accuracy = location.accuracy
                        }
                    )
                |> Result.mapError Decode.errorToString

        "geolocation.error" ->
            Err
                (Decode.decodeValue (Decode.field "message" Decode.string) bridgeEvent.payload
                    |> Result.withDefault "Unknown geolocation error"
                )

        other ->
            Err ("Unexpected geolocation event: " ++ other)


decodePosition : Decode.Decoder { latitude : Float, longitude : Float, accuracy : Float }
decodePosition =
    Decode.map3 (\lat lon acc -> { latitude = lat, longitude = lon, accuracy = acc })
        (Decode.field "latitude" Decode.float)
        (Decode.field "longitude" Decode.float)
        (Decode.field "accuracy" Decode.float)
