module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion as Companion
import Pebble.Companion.Calendar as Calendar
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { lastTitle : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotNext (Result String (Maybe Calendar.CalendarEvent))
    | GotCalendarPush (Result String (List Calendar.CalendarEvent))


init : Platform.Flags -> ( Model, Cmd Msg )
init _ =
    ( { lastTitle = "" }, Calendar.current GotNext )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestCalendar) ->
            ( model, Calendar.current GotNext )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotNext (Ok (Just event)) ->
            let
                ( hour, minute ) =
                    eventTime event.startMillis
            in
            ( { model | lastTitle = event.title }
            , Phone.sendPhoneToWatch (ProvideNextEvent event.title hour minute)
            )

        GotNext (Ok Nothing) ->
            ( model, Phone.sendPhoneToWatch NoUpcomingEvents )

        GotNext (Err _) ->
            ( model, Cmd.none )

        GotCalendarPush (Ok events) ->
            case events of
                event :: _ ->
                    let
                        ( hour, minute ) =
                            eventTime event.startMillis
                    in
                    ( { model | lastTitle = event.title }
                    , Phone.sendPhoneToWatch (ProvideNextEvent event.title hour minute)
                    )

                [] ->
                    ( model, Phone.sendPhoneToWatch NoUpcomingEvents )

        GotCalendarPush (Err _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Companion.batch [ Calendar.part GotCalendarPush ]
        ]


main : Platform.Program Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


eventTime : Int -> ( Int, Int )
eventTime startMillis =
    let
        totalMinutes =
            (startMillis // 60000) + 0
    in
    ( modBy 24 (totalMinutes // 60), modBy 60 totalMinutes )
