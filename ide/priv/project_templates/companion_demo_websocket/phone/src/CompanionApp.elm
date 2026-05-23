module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WebSocketStatus(..))
import Pebble.Companion.Phone as Phone
import Pebble.Companion.WebSocket as WebSocket
import Platform


type alias Model =
    { status : WebSocketStatus
    , statusDetail : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | WebSocketEvent WebSocket.Event
    | WebSocketCommand (Result String ())
    | Connected (Result String ())


init : () -> ( Model, Cmd Msg )
init _ =
    ( { status = Closed, statusDetail = "connecting" }
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
            if model.status == Open then
                ( model, WebSocket.send "ping" WebSocketCommand )

            else
                ( model, pushStatus model )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        Connected (Ok ()) ->
            let
                next =
                    { status = Open, statusDetail = "connected" }
            in
            ( next, pushStatus next )

        Connected (Err error) ->
            let
                next =
                    { status = Error, statusDetail = error }
            in
            ( next, pushStatus next )

        WebSocketEvent event ->
            case event of
                WebSocket.Opened ->
                    let
                        next =
                            { status = Open, statusDetail = "open" }
                    in
                    ( next, pushStatus next )

                WebSocket.Closed _ ->
                    let
                        next =
                            { status = Closed, statusDetail = "closed" }
                    in
                    ( next, pushStatus next )

                WebSocket.Message text ->
                    let
                        next =
                            { status = Open, statusDetail = truncate text 24 }
                    in
                    ( next, pushStatus next )

                WebSocket.Error error ->
                    let
                        next =
                            { status = Error, statusDetail = error }
                    in
                    ( next, pushStatus next )

                WebSocket.Unknown _ ->
                    ( model, Cmd.none )

        WebSocketCommand (Ok ()) ->
            ( model, Cmd.none )

        WebSocketCommand (Err error) ->
            let
                next =
                    { status = Error, statusDetail = error }
            in
            ( next, pushStatus next )


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
    Phone.sendPhoneToWatch (ProvideWebSocketStatus model.status model.statusDetail)


truncate : String -> Int -> String
truncate text maxLen =
    if String.length text <= maxLen then
        text

    else
        String.left (maxLen - 1) text ++ "…"
