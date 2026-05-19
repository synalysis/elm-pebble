module Pebble.Companion.Calendar exposing (CalendarEvent, Event(..), decode, nextEvent, subscribe, upcoming)

{-| Calendar information exposed by the companion bridge.

# Types
@docs CalendarEvent, Event

# Commands
@docs nextEvent, upcoming, subscribe

# Events
@docs decode

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| A calendar entry normalized for companion apps.
-}
type alias CalendarEvent =
    { id : String
    , title : String
    , location : Maybe String
    , startMillis : Int
    , endMillis : Int
    , allDay : Bool
    }


{-| Calendar events emitted by the companion bridge.
-}
type Event
    = Next (Maybe CalendarEvent)
    | Upcoming (List CalendarEvent)
    | Error String
    | Unknown String


{-| Request the next calendar event, if available.
-}
nextEvent : String -> CommandEnvelope
nextEvent id =
    Command.command id "calendar" "nextEvent"


{-| Request a bounded list of upcoming calendar events.
-}
upcoming : String -> Int -> CommandEnvelope
upcoming id limit =
    Command.command id "calendar" "upcoming"
        |> Command.withPayload (Encode.object [ ( "limit", Encode.int limit ) ])


{-| Subscribe to calendar changes when the platform bridge supports them.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "calendar" "subscribe"


{-| Decode a pushed calendar bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "calendar.next" ->
            case Decode.decodeValue (Decode.field "event" (Decode.nullable decodeCalendarEvent)) bridgeEvent.payload of
                Ok event ->
                    Next event

                Err error ->
                    Error (Decode.errorToString error)

        "calendar.upcoming" ->
            case Decode.decodeValue (Decode.field "events" (Decode.list decodeCalendarEvent)) bridgeEvent.payload of
                Ok events ->
                    Upcoming events

                Err error ->
                    Error (Decode.errorToString error)

        "calendar.error" ->
            Error (decodeErrorMessage bridgeEvent.payload "Calendar unavailable")

        other ->
            Unknown other


decodeCalendarEvent : Decode.Decoder CalendarEvent
decodeCalendarEvent =
    Decode.map6 CalendarEvent
        (Decode.field "id" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.maybe (Decode.field "location" Decode.string))
        (Decode.field "startMillis" Decode.int)
        (Decode.field "endMillis" Decode.int)
        (Decode.field "allDay" Decode.bool)


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
