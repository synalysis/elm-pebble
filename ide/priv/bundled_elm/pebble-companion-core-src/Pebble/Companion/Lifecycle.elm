module Pebble.Companion.Lifecycle exposing
    ( Event(..)
    , onLifecycle
    )

{-| Observe phone companion lifecycle events.

    subscriptions _ =
        Lifecycle.onLifecycle LifecycleChanged

# Events

@docs Event

# Subscriptions

@docs onLifecycle

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Platform as Platform


{-| Lifecycle events emitted by the companion bridge.
-}
type Event
    = Ready
    | ShowConfiguration
    | WebViewClosed (Maybe String)
    | VisibilityChanged Bool
    | Unknown String


{-| Receive pushed lifecycle events from the companion bridge.

Registering this subscription also tells the bridge to send lifecycle updates.
-}
onLifecycle : (Event -> msg) -> Sub msg
onLifecycle toMsg =
    Platform.subscribe (handler toMsg)


{-| Platform router handler for lifecycle events.
-}
handler toMsg =
    Platform.handler lifecycleInterest decodeLifecycleEvent toMsg


lifecycleInterest =
    Platform.interest
        { id = "lifecycle"
        , subscribeCommand =
            Just <|
                Command.command "lifecycle-subscribe" "lifecycle" "subscribe"
        , eventPrefixes = [ "lifecycle." ]
        , resultIdPrefixes = []
        }


decodeLifecycleEvent : Decode.Value -> Result String Event
decodeLifecycleEvent value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            Ok (decodeBridgeEvent event)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Event
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "lifecycle.ready" ->
            Ready

        "lifecycle.showConfiguration" ->
            ShowConfiguration

        "lifecycle.webviewclosed" ->
            WebViewClosed
                (Decode.decodeValue (Decode.maybe (Decode.field "response" Decode.string)) bridgeEvent.payload
                    |> Result.withDefault Nothing
                )

        "lifecycle.visibility" ->
            VisibilityChanged
                (Decode.decodeValue (Decode.field "visible" Decode.bool) bridgeEvent.payload
                    |> Result.withDefault True
                )

        other ->
            Unknown other
