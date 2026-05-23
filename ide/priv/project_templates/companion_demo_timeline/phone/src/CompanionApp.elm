module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Json.Encode as Encode
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Timeline as Timeline
import Platform


type alias Model =
    { token : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotToken (Result String String)
    | PinInserted (Result String ())


init : () -> ( Model, Cmd Msg )
init _ =
    ( { token = "" }
    , Cmd.batch
        [ Timeline.setupToken
        , Timeline.setupCommands
        , Timeline.getToken GotToken
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestTimelineToken) ->
            ( model, Timeline.getToken GotToken )

        FromWatch (Ok InsertDemoPin) ->
            ( model, Timeline.insertPin demoPinJson PinInserted )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotToken (Ok token) ->
            ( { model | token = token }
            , Phone.sendPhoneToWatch (ProvideTimelineToken token)
            )

        GotToken (Err _) ->
            ( model, Phone.sendPhoneToWatch (ProvideTimelineStatus 1) )

        PinInserted (Ok ()) ->
            ( model, Phone.sendPhoneToWatch (ProvideTimelineStatus 0) )

        PinInserted (Err _) ->
            ( model, Phone.sendPhoneToWatch (ProvideTimelineStatus 1) )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Timeline.onToken GotToken
        , Timeline.onCommands PinInserted
        ]


main : Platform.Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


demoPinJson : Encode.Value
demoPinJson =
    Encode.object
        [ ( "id", Encode.string "companion-demo-pin" )
        , ( "time", Encode.int 0 )
        , ( "duration", Encode.int 60 )
        , ( "layout", Encode.string "generic" )
        , ( "type", Encode.string "generic" )
        , ( "title", Encode.string "Companion demo" )
        , ( "subtitle", Encode.string "Timeline pin" )
        ]
