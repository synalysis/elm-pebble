module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Dict
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { lastWatch : String
    , lastPhone : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { lastWatch = "--", lastPhone = "--" }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok Ping) ->
            ( { model | lastWatch = "Ping", lastPhone = "Pong" }
            , Phone.sendPhoneToWatch Pong
            )

        FromWatch (Ok (SendColor color)) ->
            ( { model | lastWatch = "SendColor", lastPhone = "EchoColor" }
            , Phone.sendPhoneToWatch (EchoColor color)
            )

        FromWatch (Ok (SendMeasure measure)) ->
            ( { model | lastWatch = "SendMeasure", lastPhone = "EchoMeasure" }
            , Phone.sendPhoneToWatch (EchoMeasure measure)
            )

        FromWatch (Ok (SendPoint point)) ->
            ( { model | lastWatch = "SendPoint", lastPhone = "EchoPoint" }
            , Phone.sendPhoneToWatch (EchoPoint point)
            )

        FromWatch (Ok (SendCounts counts)) ->
            ( { model | lastWatch = "SendCounts", lastPhone = "EchoCounts" }
            , Phone.sendPhoneToWatch (EchoCounts counts)
            )

        FromWatch (Ok RequestPhoneExtras) ->
            ( { model | lastWatch = "RequestPhoneExtras", lastPhone = "Push*" }
            , Cmd.batch
                [ Phone.sendPhoneToWatch (PushBool True)
                , Phone.sendPhoneToWatch (PushString "elm")
                , Phone.sendPhoneToWatch (PushPoints [ { x = 4, y = 5 } ])
                , Phone.sendPhoneToWatch (PushLabels (Dict.fromList [ ( "k", 9 ) ]))
                ]
            )

        FromWatch (Err err) ->
            ( { model | lastWatch = "ERR: " ++ err }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Phone.onWatchToPhone FromWatch


main : Platform.Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
