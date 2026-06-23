module Pebble.Companion.Notifications exposing
    ( NotificationStatus
    , current
    , onNotificationStatus
    , setup
    )

{-| Phone notification status helpers for companion apps.

    import Pebble.Companion.Notifications as Notifications

    type Msg
        = GotNotifications (Result String Notifications.NotificationStatus)

    init _ =
        ( model, Notifications.current GotNotifications )

    subscriptions _ =
        Notifications.onNotificationStatus GotNotifications

For a runnable example, use the **companion-demo-phone-status** project template.

# Types

@docs NotificationStatus

# Commands

@docs current, setup

# Subscriptions

@docs onNotificationStatus

-}

import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Notification settings reported by the companion bridge.
-}
type alias NotificationStatus =
    { quietHours : Bool
    , notificationsEnabled : Bool
    }


{-| Request the current notification status.
-}
current : (Result String NotificationStatus -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "notifications-status" "notifications" "status" decodeResponse


{-| Receive pushed notification status updates from the companion bridge.

Registering this subscription also tells the bridge to send notification updates.
-}
onNotificationStatus : (Result String NotificationStatus -> msg) -> Sub msg
onNotificationStatus toMsg =
    Platform.subscribe (handler toMsg)


{-| Register this platform handler with the companion bridge.
-}
setup : Cmd msg
setup =
    Platform.setup notificationsInterest


{-| Platform router handler for notification events and responses.
-}
handler toMsg =
    Platform.handler notificationsInterest decodeNotifications toMsg


notificationsInterest =
    Platform.interest
        { id = "notifications"
        , subscribeCommand =
            Just <|
                Command.command "notifications-subscribe" "notifications" "subscribe"
        , eventPrefixes = [ "notifications." ]
        , resultIdPrefixes = [ "notifications-" ]
        }


decodeResponse : Decode.Value -> Result String NotificationStatus
decodeResponse value =
    decodeNotifications value


decodeNotifications : Decode.Value -> Result String NotificationStatus
decodeNotifications value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


decodeBridgeResult : Decode.Value -> Result String NotificationStatus
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Notification response missing payload"

                    Just payload ->
                        decodeBridgeEvent { event = "notifications.status", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String NotificationStatus
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "notifications.status" ->
            Decode.decodeValue decodeStatus bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "notifications.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Notification status unavailable")

        other ->
            Err ("Unexpected notifications event: " ++ other)


decodeStatus : Decode.Decoder NotificationStatus
decodeStatus =
    Decode.map2 NotificationStatus
        (Decode.field "quietHours" Decode.bool)
        (Decode.field "notificationsEnabled" Decode.bool)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Notification status unavailable"


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
