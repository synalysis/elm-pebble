module Pebble.Companion.Connectivity exposing
    ( Connectivity(..)
    , current
    , onConnectivity
    , setup
    )

{-| Phone internet connectivity exposed by the companion bridge.

This reports whether the phone companion runtime considers itself online. It
does **not** describe watch-to-phone Bluetooth connection — use
`Pebble.System.connectionStatus` on the watch for that.

    init _ =
        ( model, Connectivity.current ConnectivityChanged )

    subscriptions _ =
        Connectivity.onConnectivity ConnectivityChanged

# Types

@docs Connectivity

# Commands

@docs current

# Subscriptions

@docs onConnectivity

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Phone connectivity state reported by the companion bridge.
-}
type Connectivity
    = Online
    | Offline


{-| Request the current phone connectivity state.
-}
current : (Connectivity -> msg) -> Cmd msg
current toMsg =
    Phone.send (Result.withDefault Offline >> toMsg) <|
        Phone.request "connectivity-status" "network" "status" decodeResponse


{-| Receive pushed connectivity updates from the companion bridge.

Registering this subscription also tells the bridge to send connectivity updates.
-}
onConnectivity : (Connectivity -> msg) -> Sub msg
onConnectivity toMsg =
    Platform.subscribe (handler toMsg)


setup : Cmd msg
setup =
    Platform.setup connectivityInterest


{-| Platform router handler for connectivity events and responses.
-}
handler toMsg =
    Platform.handler connectivityInterest decodeConnectivityMsg (Result.withDefault Offline >> toMsg)


connectivityInterest =
    Platform.interest
        { id = "connectivity"
        , subscribeCommand =
            Just <|
                Command.command "connectivity-subscribe" "network" "subscribe"
        , eventPrefixes = [ "network." ]
        , resultIdPrefixes = [ "connectivity-" ]
        }


decodeConnectivityMsg : Decode.Value -> Result String Connectivity
decodeConnectivityMsg value =
    decodeConnectivity value
        |> Result.withDefault Offline
        |> Ok


decodeResponse : Decode.Value -> Result String Connectivity
decodeResponse value =
    decodeConnectivity value


decodeConnectivity : Decode.Value -> Result String Connectivity
decodeConnectivity value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            Ok (decodeBridgeEvent event)

        Err _ ->
            decodeBridgeResult value


decodeBridgeResult : Decode.Value -> Result String Connectivity
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Ok Offline

                    Just payload ->
                        Ok <|
                            decodeBridgeEvent <|
                                { event = "network.status", payload = payload }

            else
                Ok Offline

        Err _ ->
            Ok Offline


decodeBridgeEvent : BridgeEvent -> Connectivity
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "network.status" ->
            Decode.decodeValue (Decode.field "online" Decode.bool) bridgeEvent.payload
                |> Result.withDefault False
                |> connectivityFromOnlineFlag

        _ ->
            Offline


connectivityFromOnlineFlag : Bool -> Connectivity
connectivityFromOnlineFlag online =
    if online then
        Online

    else
        Offline
