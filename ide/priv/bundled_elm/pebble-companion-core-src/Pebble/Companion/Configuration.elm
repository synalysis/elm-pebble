module Pebble.Companion.Configuration exposing
    ( onClosed
    , open
    , setup
    )

{-| Open and observe the Pebble companion configuration page.

    init _ =
        ( model, Configuration.open "https://example.com/config" )

    subscriptions _ =
        Configuration.onClosed ConfigurationClosed

# Commands

@docs open

# Subscriptions

@docs onClosed

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Configuration lifecycle events reported by the bridge.
-}
type Event
    = Closed (Maybe String)
    | Unknown String


{-| Ask the companion bridge to open a configuration URL.
-}
open : String -> Cmd msg
open url =
    Phone.sendBridgeCommand <|
        (Command.command "configuration-open" "configuration" "open"
            |> Command.withPayload (Encode.object [ ( "url", Encode.string url ) ]))


{-| Receive configuration close events from the companion bridge.

Registering this subscription also tells the bridge to send configuration events.
-}
onClosed : (Maybe String -> msg) -> Sub msg
onClosed toMsg =
    Platform.subscribe (handler toMsg)


setup : Cmd msg
setup =
    Platform.setup configurationInterest


toClosedMsg : (Maybe String -> msg) -> (Event -> msg)
toClosedMsg toMsg event =
    case event of
        Closed response ->
            toMsg response

        Unknown _ ->
            toMsg Nothing


{-| Platform router handler for configuration close events.
-}
handler toMsg =
    Platform.handler configurationInterest decodeConfigurationEvent <|
        Result.withDefault (Closed Nothing) >> toClosedMsg toMsg


configurationInterest =
    Platform.interest
        { id = "configuration"
        , subscribeCommand =
            Just <|
                Command.command "configuration-subscribe" "configuration" "subscribe"
        , eventPrefixes = [ "configuration." ]
        , resultIdPrefixes = []
        }


decodeConfigurationEvent : Decode.Value -> Result String Event
decodeConfigurationEvent value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            Ok (decodeBridgeEvent event)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Event
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "configuration.closed" ->
            Closed
                (Decode.decodeValue (Decode.maybe (Decode.field "response" Decode.string)) bridgeEvent.payload
                    |> Result.withDefault Nothing
                )

        other ->
            Unknown other
