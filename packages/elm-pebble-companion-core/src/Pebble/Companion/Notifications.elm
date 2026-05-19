module Pebble.Companion.Notifications exposing (Event(..), NotificationStatus, decode, status, subscribe)

{-| Notification and quiet-hours status exposed by the companion bridge.

# Types
@docs NotificationStatus, Event

# Commands
@docs status, subscribe

# Events
@docs decode

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Phone notification availability and quiet-hours state.
-}
type alias NotificationStatus =
    { quietHours : Bool
    , notificationsEnabled : Bool
    }


{-| Notification status events emitted by the companion bridge.
-}
type Event
    = Status NotificationStatus
    | Error String
    | Unknown String


{-| Request the current notification status.
-}
status : String -> CommandEnvelope
status id =
    Command.command id "notifications" "status"


{-| Subscribe to notification status changes when supported.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "notifications" "subscribe"


{-| Decode a pushed notification bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "notifications.status" ->
            case Decode.decodeValue decodeStatus bridgeEvent.payload of
                Ok value ->
                    Status value

                Err error ->
                    Error (Decode.errorToString error)

        "notifications.error" ->
            Error (decodeErrorMessage bridgeEvent.payload "Notification status unavailable")

        other ->
            Unknown other


decodeStatus : Decode.Decoder NotificationStatus
decodeStatus =
    Decode.map2 NotificationStatus
        (Decode.field "quietHours" Decode.bool)
        (Decode.field "notificationsEnabled" Decode.bool)


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
