module Pebble.Companion.Timeline exposing (deletePin, getToken, insertPin)

{-| Timeline commands for companion-driven pins.

    Pebble.Companion.Timeline.insertPin "pin-create" pinJson

# Commands
@docs getToken, insertPin, deletePin

-}

import Json.Encode as Encode
import Pebble.Companion.Command as Command
import Pebble.Companion.Contract exposing (CommandEnvelope)


{-| Request the timeline token for the current user.
-}
getToken : String -> CommandEnvelope
getToken id =
    Command.command id "timeline" "getToken"


{-| Insert or update a timeline pin from encoded pin JSON.
-}
insertPin : String -> Encode.Value -> CommandEnvelope
insertPin id pinJson =
    Command.command id "timeline" "insertPin"
        |> Command.withPayload (Encode.object [ ( "pin", pinJson ) ])


{-| Delete a timeline pin by id.
-}
deletePin : String -> String -> CommandEnvelope
deletePin id pinId =
    Command.command id "timeline" "deletePin"
        |> Command.withPayload (Encode.object [ ( "pinId", Encode.string pinId ) ])
