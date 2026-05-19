module Companion.Notifications exposing (NotificationStatus, current, onNotifications, subscribe)

{-| Notification and quiet-hours helpers for companion apps. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Notifications as Notifications


type alias NotificationStatus =
    Notifications.NotificationStatus


current : Cmd msg
current =
    Notifications.status "notifications-status"
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Notifications.subscribe "notifications-subscribe"
        |> Phone.sendBridgeCommand


onNotifications : (Result String NotificationStatus -> msg) -> Sub msg
onNotifications toMsg =
    Phone.onRawMessage (decodeNotifications >> toMsg)


decodeNotifications : Decode.Value -> Result String NotificationStatus
decodeNotifications value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Notifications.decode event of
                Notifications.Status status ->
                    Ok status

                Notifications.Error error ->
                    Err error

                Notifications.Unknown eventName ->
                    Err ("Unexpected notifications event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
