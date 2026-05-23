module Pebble.Companion.Calendar exposing
    ( CalendarEvent
    , current
    , onCalendar
    , part
    , partCurrent
    , partUpcoming
    , upcoming
    )

{-| Calendar helpers for companion apps.

# Types

@docs CalendarEvent

# Commands

@docs current, upcoming

# Subscriptions

@docs onCalendar, part, partCurrent, partUpcoming

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


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


{-| Request the next calendar event, if available.
-}
current : (Result String (Maybe CalendarEvent) -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "calendar-next" "calendar" "nextEvent" decodeCurrentResponse


{-| Request a bounded list of upcoming calendar events.
-}
upcoming : Int -> (Result String (List CalendarEvent) -> msg) -> Cmd msg
upcoming limit toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload "calendar-upcoming" "calendar" "upcoming"
            (Encode.object [ ( "limit", Encode.int limit ) ])
            decodeUpcomingResponse


{-| Receive pushed calendar updates from the companion bridge.

Registering this subscription also tells the bridge to send calendar updates.
-}
onCalendar : (Result String (List CalendarEvent) -> msg) -> Sub msg
onCalendar toMsg =
    Platform.with [ handler toMsg ]


{-| Platform listener for use with `Platform.batch` or `Pebble.Companion.batch`.
-}
part : (Result String (List CalendarEvent) -> msg) -> Platform.Part msg
part toMsg =
    Platform.part (handler toMsg)


{-| Platform listener for `current` command responses.
-}
partCurrent : (Result String (Maybe CalendarEvent) -> msg) -> Platform.Part msg
partCurrent toMsg =
    Platform.part (handlerCurrent toMsg)


{-| Platform listener for `upcoming` command responses.
-}
partUpcoming : (Result String (List CalendarEvent) -> msg) -> Platform.Part msg
partUpcoming toMsg =
    Platform.part (handlerUpcoming toMsg)


handler toMsg =
    Platform.handler calendarPushInterest decodeCalendar toMsg


handlerCurrent toMsg =
    Platform.handler calendarCurrentInterest decodeCurrentResponse toMsg


handlerUpcoming toMsg =
    Platform.handler calendarUpcomingInterest decodeUpcomingResponse toMsg


calendarPushInterest =
    Platform.interest
        { id = "calendar"
        , subscribeCommand =
            Just <|
                Command.command "calendar-subscribe" "calendar" "subscribe"
        , eventPrefixes = [ "calendar." ]
        , resultIdPrefixes = []
        }


calendarUpcomingInterest =
    Platform.interest
        { id = "calendar-upcoming"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "calendar-upcoming" ]
        }


calendarCurrentInterest =
    Platform.interest
        { id = "calendar-next"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "calendar-next" ]
        }


decodeCurrentResponse : Decode.Value -> Result String (Maybe CalendarEvent)
decodeCurrentResponse value =
    decodeCalendarEventResponse value


decodeUpcomingResponse : Decode.Value -> Result String (List CalendarEvent)
decodeUpcomingResponse value =
    decodeCalendar value


decodeCalendar : Decode.Value -> Result String (List CalendarEvent)
decodeCalendar value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


decodeCalendarEventResponse : Decode.Value -> Result String (Maybe CalendarEvent)
decodeCalendarEventResponse value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeNextBridgeEvent event

        Err _ ->
            decodeNextBridgeResult value


decodeBridgeResult : Decode.Value -> Result String (List CalendarEvent)
decodeBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Ok []

                    Just payload ->
                        decodeBridgeEvent { event = "calendar.upcoming", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeNextBridgeResult : Decode.Value -> Result String (Maybe CalendarEvent)
decodeNextBridgeResult value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Ok Nothing

                    Just payload ->
                        decodeNextBridgeEvent { event = "calendar.next", payload = payload }

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeEvent : BridgeEvent -> Result String (List CalendarEvent)
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "calendar.next" ->
            decodeNextBridgeEvent bridgeEvent
                |> Result.map (Maybe.map List.singleton >> Maybe.withDefault [])

        "calendar.upcoming" ->
            Decode.decodeValue (Decode.field "events" (Decode.list decodeCalendarEvent)) bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "calendar.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Calendar unavailable")

        other ->
            Err ("Unexpected calendar event: " ++ other)


decodeNextBridgeEvent : BridgeEvent -> Result String (Maybe CalendarEvent)
decodeNextBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "calendar.next" ->
            Decode.decodeValue (Decode.field "event" (Decode.nullable decodeCalendarEvent)) bridgeEvent.payload
                |> Result.mapError Decode.errorToString

        "calendar.error" ->
            Err (decodeErrorMessage bridgeEvent.payload "Calendar unavailable")

        other ->
            Err ("Unexpected calendar event: " ++ other)


decodeCalendarEvent : Decode.Decoder CalendarEvent
decodeCalendarEvent =
    Decode.map6 CalendarEvent
        (Decode.field "id" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.maybe (Decode.field "location" Decode.string))
        (Decode.field "startMillis" Decode.int)
        (Decode.field "endMillis" Decode.int)
        (Decode.field "allDay" Decode.bool)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Calendar unavailable"


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
