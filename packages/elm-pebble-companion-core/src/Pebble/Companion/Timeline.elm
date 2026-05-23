module Pebble.Companion.Timeline exposing
    ( deletePin
    , getToken
    , insertPin
    , onCommands
    , onToken
    , setupCommands
    , setupToken
    )

{-| Timeline commands for companion-driven pins.

    init _ =
        ( model, Timeline.getToken GotToken )

    subscriptions _ =
        Timeline.onToken GotToken

# Commands

@docs getToken, insertPin, deletePin

# Subscriptions

@docs onToken, onCommands

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Codec as Codec
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Platform as Platform


{-| Request the timeline token for the current user.
-}
getToken : (Result String String -> msg) -> Cmd msg
getToken toMsg =
    Phone.send toMsg <|
        Phone.request "timeline-get-token" "timeline" "getToken" decodeTokenResponse


{-| Insert or update a timeline pin from encoded pin JSON.
-}
insertPin : Encode.Value -> (Result String () -> msg) -> Cmd msg
insertPin pinJson toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload "timeline-insert-pin" "timeline" "insertPin"
            (Encode.object [ ( "pin", pinJson ) ])
            decodeCommandResponse


{-| Delete a timeline pin by id.
-}
deletePin : String -> (Result String () -> msg) -> Cmd msg
deletePin pinId toMsg =
    Phone.send toMsg <|
        Phone.requestWithPayload "timeline-delete-pin" "timeline" "deletePin"
            (Encode.object [ ( "pinId", Encode.string pinId ) ])
            decodeCommandResponse


{-| Receive timeline token command responses on the dedicated timeline port.
-}
onToken : (Result String String -> msg) -> Sub msg
onToken toMsg =
    Platform.subscribe (handlerToken toMsg)


{-| Receive timeline command responses on the dedicated timeline port.
-}
onCommands : (Result String () -> msg) -> Sub msg
onCommands toMsg =
    Platform.subscribe (handlerCommands toMsg)


setupToken : Cmd msg
setupToken =
    Platform.setup timelineTokenInterest


setupCommands : Cmd msg
setupCommands =
    Platform.setup timelineCommandInterest


handlerToken toMsg =
    Platform.handler timelineTokenInterest decodeTokenResponse toMsg


handlerCommands toMsg =
    Platform.handler timelineCommandInterest decodeCommandResponse toMsg


timelineTokenInterest =
    Platform.interest
        { id = "timeline-token"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "timeline-get-token" ]
        }


timelineCommandInterest =
    Platform.interest
        { id = "timeline-commands"
        , subscribeCommand = Nothing
        , eventPrefixes = []
        , resultIdPrefixes = [ "timeline-insert-pin", "timeline-delete-pin" ]
        }


decodeTokenResponse : Decode.Value -> Result String String
decodeTokenResponse value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                case envelope.payload of
                    Nothing ->
                        Err "Timeline token response missing payload"

                    Just payload ->
                        Decode.decodeValue (Decode.field "token" Decode.string) payload
                            |> Result.mapError Decode.errorToString

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeCommandResponse : Decode.Value -> Result String ()
decodeCommandResponse value =
    case Decode.decodeValue Codec.decodeResult value of
        Ok envelope ->
            if envelope.ok then
                Ok ()

            else
                Err (decodeBridgeError envelope)

        Err error ->
            Err (Decode.errorToString error)


decodeBridgeError : Pebble.Companion.Contract.ResultEnvelope -> String
decodeBridgeError envelope =
    case envelope.error of
        Just error ->
            error.message

        Nothing ->
            "Timeline command failed"
