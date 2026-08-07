port module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WebSocketStatus(..))
import Pebble.Companion.Phone as Phone
import Platform
import WebsocketSimple as WebSocket exposing (RawMsg(..))


port wsCmd : WebSocket.CommandPort msg


port wsMsg : WebSocket.EventPort msg


type alias Model =
    { status : WebSocketStatus
    , statusDetail : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | WebSocketEvent WebSocket.RawMsg


init : () -> ( Model, Cmd Msg )
init _ =
    ( { status = Closed, statusDetail = "connecting" }
    , WebSocket.open wsCmd "wss://ws.postman-echo.com/raw"
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestWebSocketStatus) ->
            ( model, pushStatus model )

        FromWatch (Ok PingWebSocket) ->
            if model.status == Open then
                ( model, WebSocket.send wsCmd (WebSocket.Transmit "ping") )

            else
                ( model, pushStatus model )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        WebSocketEvent (Connected _) ->
            let
                next =
                    { status = Open, statusDetail = "open" }
            in
            ( next, pushStatus next )

        WebSocketEvent (Disconnected _) ->
            let
                next =
                    { status = Closed, statusDetail = "closed" }
            in
            ( next, pushStatus next )

        WebSocketEvent (Text text) ->
            let
                next =
                    { status = Open, statusDetail = truncate text 24 }
            in
            ( next, pushStatus next )

        WebSocketEvent (TransportError error) ->
            let
                next =
                    { status = Error, statusDetail = WebSocket.errorToString error }
            in
            ( next, pushStatus next )

        WebSocketEvent (Binary _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Sub.map WebSocketEvent (WebSocket.subscribe wsMsg)
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
