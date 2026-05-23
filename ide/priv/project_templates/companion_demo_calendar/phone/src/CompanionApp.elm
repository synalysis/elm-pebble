module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion.Calendar as Calendar
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { lastTitle : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotCalendar (Result String (List Calendar.CalendarEvent))


init : Platform.Flags -> ( Model, Cmd Msg )
init _ =
    ( { lastTitle = "" }
    , Calendar.current (GotCalendar << Result.map maybeAsList)
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestCalendar) ->
            ( model, Calendar.current (GotCalendar << Result.map maybeAsList) )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotCalendar (Ok events) ->
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

        GotCalendar (Err _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Calendar.onCalendar GotCalendar
        ]


main : Platform.Program Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


maybeAsList : Maybe Calendar.CalendarEvent -> List Calendar.CalendarEvent
maybeAsList event =
    case event of
        Nothing ->
            []

        Just value ->
            [ value ]


eventTime : Int -> ( Int, Int )
eventTime startMillis =
    let
        totalMinutes =
            (startMillis // 60000) + 0
    in
    ( modBy 24 (totalMinutes // 60), modBy 60 totalMinutes )
