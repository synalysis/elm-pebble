module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion.Geolocation as Geolocation
import Pebble.Companion.Phone as Phone
import Platform


type alias Model =
    { latitudeE6 : Int
    , longitudeE6 : Int
    , accuracyM : Int
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotPosition (Result String Geolocation.Location)


init : Platform.Flags -> ( Model, Cmd Msg )
init _ =
    ( emptyModel, Geolocation.currentPosition GotPosition )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestPosition) ->
            ( model, Geolocation.currentPosition GotPosition )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotPosition (Ok location) ->
            let
                latitudeE6 =
                    round (location.latitude * 1000000)

                longitudeE6 =
                    round (location.longitude * 1000000)

                accuracyM =
                    round location.accuracy
            in
            ( { model | latitudeE6 = latitudeE6, longitudeE6 = longitudeE6, accuracyM = accuracyM }
            , Phone.sendPhoneToWatch (ProvidePosition latitudeE6 longitudeE6 accuracyM)
            )

        GotPosition (Err _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Geolocation.onCurrentPosition GotPosition
        ]


main : Platform.Program Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


emptyModel : Model
emptyModel =
    { latitudeE6 = 0
    , longitudeE6 = 0
    , accuracyM = 0
    }
