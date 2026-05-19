module Pebble.Companion.Locale exposing (Event(..), LocaleInfo, decode, status, subscribe)

{-| Phone locale and regional preferences exposed by the companion bridge.

# Types
@docs LocaleInfo, Event

# Commands
@docs status, subscribe

# Events
@docs decode

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Locale, language, region, and clock format from phone context.
-}
type alias LocaleInfo =
    { locale : String
    , language : String
    , region : String
    , uses24h : Bool
    }


{-| Locale events emitted by the companion bridge.
-}
type Event
    = Status LocaleInfo
    | Error String
    | Unknown String


{-| Request the current phone locale status.
-}
status : String -> CommandEnvelope
status id =
    Command.command id "locale" "status"


{-| Subscribe to locale changes when supported.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "locale" "subscribe"


{-| Decode a pushed locale bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "locale.status" ->
            case Decode.decodeValue decodeLocaleInfo bridgeEvent.payload of
                Ok info ->
                    Status info

                Err error ->
                    Error (Decode.errorToString error)

        "locale.error" ->
            Error (decodeErrorMessage bridgeEvent.payload "Locale unavailable")

        other ->
            Unknown other


decodeLocaleInfo : Decode.Decoder LocaleInfo
decodeLocaleInfo =
    Decode.map4 LocaleInfo
        (Decode.field "locale" Decode.string)
        (Decode.field "language" Decode.string)
        (Decode.field "region" Decode.string)
        (Decode.field "uses24h" Decode.bool)


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
