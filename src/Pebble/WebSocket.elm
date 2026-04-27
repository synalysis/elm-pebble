module Pebble.WebSocket exposing
    ( WebSocketState(..)
    , WebSocketMessage
    , WebSocketCmd(..)
    , connect
    , disconnect
    , send
    , sendJson
    , isConnected
    , getState
    )

{-| WebSocket support for real-time communication in Pebble applications.

# Types
@docs WebSocketState, WebSocketMessage, WebSocketCmd

# Connection Management
@docs connect, disconnect, isConnected, getState

# Sending Messages
@docs send, sendJson

-}

import Json.Encode as Encode


-- TYPES

{-| WebSocket connection states.
-}
type WebSocketState
    = Connecting
    | Connected
    | Disconnected
    | Error String


{-| WebSocket message with type and data.
-}
type alias WebSocketMessage =
    { type_ : String
    , data : String
    }


{-| Commands for WebSocket operations.
-}
type WebSocketCmd msg
    = Connect String (WebSocketState -> msg)  -- url, state update
    | Disconnect (WebSocketState -> msg)
    | Send String (Result String () -> msg)   -- message, result
    | SendJson Encode.Value (Result String () -> msg)


-- CONNECTION MANAGEMENT

{-| Connect to a WebSocket server.

    WebSocket.connect "ws://localhost:8080" ConnectionStateChanged

-}
connect : String -> (WebSocketState -> msg) -> WebSocketCmd msg
connect url toMsg =
    Connect url toMsg


{-| Disconnect from the WebSocket server.

    WebSocket.disconnect ConnectionStateChanged

-}
disconnect : (WebSocketState -> msg) -> WebSocketCmd msg
disconnect toMsg =
    Disconnect toMsg


{-| Check if currently connected.

    if WebSocket.isConnected model.websocketState then
        -- Send message
    else
        -- Show connection error

-}
isConnected : WebSocketState -> Bool
isConnected state =
    case state of
        Connected -> True
        _ -> False


{-| Get the current connection state.

    case WebSocket.getState model.websocketState of
        Connected -> "Connected"
        Connecting -> "Connecting..."
        Disconnected -> "Disconnected"
        Error message -> "Error: " ++ message

-}
getState : WebSocketState -> String
getState state =
    case state of
        Connecting -> "Connecting"
        Connected -> "Connected"
        Disconnected -> "Disconnected"
        Error message -> "Error: " ++ message


-- SENDING MESSAGES

{-| Send a text message.

    WebSocket.send "Hello, server!" MessageSent

-}
send : String -> (Result String () -> msg) -> WebSocketCmd msg
send message toMsg =
    Send message toMsg


{-| Send JSON data.

    WebSocket.sendJson 
        (Encode.object 
            [ ("type", Encode.string "chat")
            , ("message", Encode.string "Hello!")
            ]
        ) 
        MessageSent

-}
sendJson : Encode.Value -> (Result String () -> msg) -> WebSocketCmd msg
sendJson jsonData toMsg =
    SendJson jsonData toMsg 