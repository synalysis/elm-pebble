module Companion.Calendar exposing (CalendarEvent, current, onCalendar, subscribe, upcoming)

{-| Calendar helpers for companion apps. -}

import Companion.Phone as Phone
import Json.Decode as Decode
import Pebble.Companion.Calendar as Calendar
import Pebble.Companion.Codec as Codec


type alias CalendarEvent =
    Calendar.CalendarEvent


current : Cmd msg
current =
    Calendar.nextEvent "calendar-next"
        |> Phone.sendBridgeCommand


upcoming : Int -> Cmd msg
upcoming limit =
    Calendar.upcoming "calendar-upcoming" limit
        |> Phone.sendBridgeCommand


subscribe : Cmd msg
subscribe =
    Calendar.subscribe "calendar-subscribe"
        |> Phone.sendBridgeCommand


onCalendar : (Result String (List CalendarEvent) -> msg) -> Sub msg
onCalendar toMsg =
    Phone.onRawMessage (decodeCalendar >> toMsg)


decodeCalendar : Decode.Value -> Result String (List CalendarEvent)
decodeCalendar value =
    case Decode.decodeValue Codec.decodeEvent value of
        Ok event ->
            case Calendar.decode event of
                Calendar.Next maybeEvent ->
                    Ok (Maybe.withDefault [] (Maybe.map List.singleton maybeEvent))

                Calendar.Upcoming events ->
                    Ok events

                Calendar.Error error ->
                    Err error

                Calendar.Unknown eventName ->
                    Err ("Unexpected calendar event: " ++ eventName)

        Err error ->
            Err (Decode.errorToString error)
