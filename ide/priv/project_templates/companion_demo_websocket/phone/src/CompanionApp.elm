module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion.Phone as Phone
import Pebble.Companion.WebSocket as WebSocket
import Platform


type alias Model =
    { statusCode : Int
    , statusText : String
    , connected : Bool
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | WebSocketEvent WebSocket.Event
    | WebSocketCommand (Result String ())
    | Connected (Result String ())


init : () -> ( Model, Cmd Msg )
init _ =
    ( { statusCode = 0, statusText = "connecting", connected = False }
    , Cmd.batch
        [ WebSocket.setup
        , WebSocket.setupCommands
        , WebSocket.connect "wss://echo.websocket.events" Connected
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestWebSocketStatus) ->
            ( model, pushStatus model )

        FromWatch (Ok PingWebSocket) ->
            if model.connected then
                ( model, WebSocket.send "ping" WebSocketCommand )

            else
                ( model, pushStatus model )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        Connected (Ok ()) ->
            ( { model | connected = True, statusCode = 1, statusText = "connected" }
            , pushStatus { model | connected = True, statusCode = 1, statusText = "connected" }
            )

        Connected (Err error) ->
            ( { model | connected = False, statusCode = 2, statusText = error }
            , pushStatus { model | connected = False, statusCode = 2, statusText = error }
            )

        WebSocketEvent event ->
            case event of
                WebSocket.Opened ->
                    ( { model | connected = True, statusCode = 1, statusText = "open" }
                    , pushStatus { model | connected = True, statusCode = 1, statusText = "open" }
                    )

                WebSocket.Closed _ ->
                    ( { model | connected = False, statusCode = 0, statusText = "closed" }
                    , pushStatus { model | connected = False, statusCode = 0, statusText = "closed" }
                    )

                WebSocket.Message text ->
                    ( { model | statusCode = 1, statusText = truncate text 24 }
                    , pushStatus { model | statusCode = 1, statusText = truncate text 24 }
                    )

                WebSocket.Error error ->
                    ( { model | connected = False, statusCode = 2, statusText = error }
                    , pushStatus { model | connected = False, statusCode = 2, statusText = error }
                    )

                WebSocket.Unknown _ ->
                    ( model, Cmd.none )

        WebSocketCommand (Ok ()) ->
            ( model, Cmd.none )

        WebSocketCommand (Err error) ->
            ( { model | statusCode = 2, statusText = error }
            , pushStatus { model | statusCode = 2, statusText = error }
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , WebSocket.onWebSocket WebSocketEvent
        , WebSocket.onCommands WebSocketCommand
        ]


main : Platform.Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


pushStatus : Model -> Cmd Msg
pushStatus model =
    Phone.sendPhoneToWatch (ProvideWebSocketStatus model.statusCode model.statusText)


truncate : String -> Int -> String
truncate text maxLen =
    if String.length text <= maxLen then
        text

    else
        String.left (maxLen - 1) text ++ "…"
