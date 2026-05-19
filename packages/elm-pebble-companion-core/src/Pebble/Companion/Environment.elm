module Pebble.Companion.Environment exposing (EnvironmentInfo, Event(..), MoonInfo, SunInfo, TideInfo, current, decode, subscribe)

{-| Environmental snapshots derived from phone/Pebble context.

The bridge owns the calculation source. Apps receive typed sun, moon, and tide
values without parsing labels or guessing fields.

# Types
@docs SunInfo, MoonInfo, TideInfo, EnvironmentInfo, Event

# Commands
@docs current, subscribe

# Events
@docs decode

-}

import Json.Decode as Decode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (BridgeEvent, CommandEnvelope)


{-| Sun cycle information in local minutes after midnight.
-}
type alias SunInfo =
    { sunriseMin : Int
    , sunsetMin : Int
    , polarDay : Bool
    }


{-| Moon timing and phase information.
-}
type alias MoonInfo =
    { moonriseMin : Maybe Int
    , moonsetMin : Maybe Int
    , phaseE6 : Int
    }


{-| Tide information for the next notable tide event.
-}
type alias TideInfo =
    { nextMin : Int
    , levelCm : Int
    , rising : Bool
    }


{-| Available environmental information from the companion bridge.
-}
type alias EnvironmentInfo =
    { sun : Maybe SunInfo
    , moon : Maybe MoonInfo
    , tide : Maybe TideInfo
    }


{-| Environment events emitted by the companion bridge.
-}
type Event
    = Current EnvironmentInfo
    | Error String
    | Unknown String


{-| Request the current environment snapshot.
-}
current : String -> CommandEnvelope
current id =
    Command.command id "environment" "current"


{-| Subscribe to environment updates when supported.
-}
subscribe : String -> CommandEnvelope
subscribe id =
    Command.command id "environment" "subscribe"


{-| Decode a pushed environment bridge event.
-}
decode : BridgeEvent -> Event
decode bridgeEvent =
    case bridgeEvent.event of
        "environment.current" ->
            case Decode.decodeValue decodeEnvironmentInfo bridgeEvent.payload of
                Ok info ->
                    Current info

                Err error ->
                    Error (Decode.errorToString error)

        "environment.error" ->
            Error (decodeErrorMessage bridgeEvent.payload "Environment unavailable")

        other ->
            Unknown other


decodeEnvironmentInfo : Decode.Decoder EnvironmentInfo
decodeEnvironmentInfo =
    Decode.map3 EnvironmentInfo
        (Decode.maybe (Decode.field "sun" decodeSunInfo))
        (Decode.maybe (Decode.field "moon" decodeMoonInfo))
        (Decode.maybe (Decode.field "tide" decodeTideInfo))


decodeSunInfo : Decode.Decoder SunInfo
decodeSunInfo =
    Decode.map3 SunInfo
        (Decode.field "sunriseMin" Decode.int)
        (Decode.field "sunsetMin" Decode.int)
        (Decode.field "polarDay" Decode.bool)


decodeMoonInfo : Decode.Decoder MoonInfo
decodeMoonInfo =
    Decode.map3 MoonInfo
        (Decode.maybe (Decode.field "moonriseMin" Decode.int))
        (Decode.maybe (Decode.field "moonsetMin" Decode.int))
        (Decode.field "phaseE6" Decode.int)


decodeTideInfo : Decode.Decoder TideInfo
decodeTideInfo =
    Decode.map3 TideInfo
        (Decode.field "nextMin" Decode.int)
        (Decode.field "levelCm" Decode.int)
        (Decode.field "rising" Decode.bool)


decodeErrorMessage : Decode.Value -> String -> String
decodeErrorMessage payload fallback =
    Decode.decodeValue (Decode.field "message" Decode.string) payload
        |> Result.withDefault fallback
