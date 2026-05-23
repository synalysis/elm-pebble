module Pebble.Companion.Calendar exposing
    ( CalendarEvent
    , current
    , onCalendar
    , onCurrent
    , onUpcoming
    , setup
    , setupCurrent
    , setupUpcoming
    , upcoming
    )

{-| Calendar helpers for companion apps.

    import Pebble.Companion.Calendar as Calendar

    type Msg
        = GotCalendar (Result String (List Calendar.CalendarEvent))

    init _ =
        ( model, Calendar.current (GotCalendar << Result.map maybeAsList) )

    subscriptions _ =
        Calendar.onCalendar GotCalendar

    maybeAsList event =
        case event of
            Nothing -> []
            Just value -> [ value ]

# Types

@docs CalendarEvent

# Commands

@docs current, upcoming, setup, setupCurrent, setupUpcoming

# Subscriptions

@docs onCalendar, onCurrent, onUpcoming

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

This registers the calendar bridge (via `setup`) before sending the request.
Pair it with `onCalendar` in subscriptions so responses can reach your `update`.
-}
current : (Result String (Maybe CalendarEvent) -> msg) -> Cmd msg
current toMsg =
    Cmd.batch
        [ setup
        , Phone.send toMsg <|
            Phone.request "calendar-next" "calendar" "nextEvent" decodeCurrentResponse
        ]


{-| Request a bounded list of upcoming calendar events.
-}
upcoming : Int -> (Result String (List CalendarEvent) -> msg) -> Cmd msg
upcoming limit toMsg =
    Cmd.batch
        [ setup
        , Phone.send toMsg <|
            Phone.requestWithPayload "calendar-upcoming" "calendar" "upcoming"
                (Encode.object [ ( "limit", Encode.int limit ) ])
                decodeUpcomingResponse
        ]


{-| Receive pushed calendar updates from the companion bridge.

Registering this subscription also tells the bridge to send calendar updates.
-}
onCalendar : (Result String (List CalendarEvent) -> msg) -> Sub msg
onCalendar toMsg =
    Platform.subscribe (handler toMsg)


{-| Receive next-event command responses on the dedicated calendar port.
-}
onCurrent : (Result String (Maybe CalendarEvent) -> msg) -> Sub msg
onCurrent toMsg =
    Platform.subscribe (handlerCurrent toMsg)


{-| Receive upcoming-events command responses on the dedicated calendar port.
-}
onUpcoming : (Result String (List CalendarEvent) -> msg) -> Sub msg
onUpcoming toMsg =
    Platform.subscribe (handlerUpcoming toMsg)


{-| Register the calendar push platform handler with the companion bridge.
-}
setup : Cmd msg
setup =
    Platform.setup calendarPushInterest


{-| Register the calendar current-event platform handler with the companion bridge.
-}
setupCurrent : Cmd msg
setupCurrent =
    Platform.setup calendarCurrentInterest


{-| Register the calendar upcoming-events platform handler with the companion bridge.
-}
setupUpcoming : Cmd msg
setupUpcoming =
    Platform.setup calendarUpcomingInterest


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
        , resultIdPrefixes = [ "calendar-" ]
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
                        if String.startsWith "calendar-next" envelope.id then
                            decodeNextBridgeEvent { event = "calendar.next", payload = payload }
                                |> Result.map
                                    (\maybeEvent ->
                                        case maybeEvent of
                                            Just event ->
                                                [ event ]

                                            Nothing ->
                                                []
                                    )

                        else
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
