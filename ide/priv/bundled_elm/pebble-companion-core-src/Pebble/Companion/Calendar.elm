module Pebble.Companion.Calendar exposing
    ( CalendarEvent
    , current
    , onCalendar
    , upcoming
    )

{-| Calendar helpers for companion apps.

# Types

@docs CalendarEvent

# Commands

@docs current, upcoming

# Subscriptions

@docs onCalendar

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent)
import Pebble.Companion.Phone as Phone
import Sub


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
current : (Result String (List CalendarEvent) -> msg) -> Cmd msg
current toMsg =
    Phone.send toMsg <|
        Phone.request "calendar-next" "calendar" "nextEvent" decodeResponse


{-| Request a bounded list of upcoming calendar events.
-}
upcoming : Int -> (Result String (List CalendarEvent) -> msg) -> Cmd msg
upcoming limit toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload "calendar-upcoming" "calendar" "upcoming"
            (Encode.object [ ( "limit", Encode.int limit ) ])
            decodeResponse


{-| Receive pushed calendar updates from the companion bridge.

Registering this subscription also tells the bridge to send calendar updates.
-}
onCalendar : (Result String (List CalendarEvent) -> msg) -> Sub msg
onCalendar toMsg =
    Sub.batch
        [ Phone.subscribeBridge <|
            Command.command "calendar-subscribe" "calendar" "subscribe"
        , Phone.onRawMessage (decodeCalendar >> toMsg)
        ]


decodeResponse : Decode.Value -> Result String (List CalendarEvent)
decodeResponse value =
    decodeCalendar value


decodeCalendar : Decode.Value -> Result String (List CalendarEvent)
decodeCalendar value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            decodeBridgeEvent event

        Err _ ->
            decodeBridgeResult value


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


decodeBridgeEvent : BridgeEvent -> Result String (List CalendarEvent)
decodeBridgeEvent bridgeEvent =
    case bridgeEvent.event of
        "calendar.next" ->
            Decode.decodeValue (Decode.field "event" (Decode.nullable decodeCalendarEvent)) bridgeEvent.payload
                |> Result.map (Maybe.withDefault [] << Maybe.map List.singleton)
                |> Result.mapError Decode.errorToString

        "calendar.upcoming" ->
            Decode.decodeValue (Decode.field "events" (Decode.list decodeCalendarEvent)) bridgeEvent.payload
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
