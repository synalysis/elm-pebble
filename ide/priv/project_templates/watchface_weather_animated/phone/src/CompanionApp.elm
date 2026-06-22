module CompanionApp exposing (main)

import Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), WatchToPhone(..), WeatherCondition(..))
import Json.Decode as Decode
import Pebble.Companion.Lifecycle as Lifecycle
import Pebble.Companion.Phone as CompanionPhone
import Pebble.Companion.Weather as Weather
import Platform


type alias Model =
    { lastResponse : Int
    , lastCondition : Maybe WeatherCondition
    , replyToWatch : Bool
    , errors : List String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotWeather (Result String Weather.WeatherUpdate)
    | LifecycleChanged Lifecycle.Event


init : Decode.Value -> ( Model, Cmd Msg )
init _ =
    ( initialModel
    , Lifecycle.setup
    )


initialModel : Model
initialModel =
    { lastResponse = 0, lastCondition = Nothing, replyToWatch = False, errors = [] }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok (RequestWeather _)) ->
            ( { model | replyToWatch = True }, refreshWeather )

        FromWatch (Err error) ->
            ( addError ("Watch message error: " ++ error) model, Cmd.none )

        LifecycleChanged Lifecycle.Ready ->
            ( model, Cmd.none )

        LifecycleChanged _ ->
            ( model, Cmd.none )

        GotWeather (Ok (Weather.Current info)) ->
            let
                condition =
                    toProtocolCondition info.condition

                alreadyCurrent =
                    model.lastResponse == info.temperatureC && model.lastCondition == Just condition
            in
            if alreadyCurrent then
                ( { model | replyToWatch = False }, Cmd.none )

            else
                ( { model
                    | lastResponse = info.temperatureC
                    , lastCondition = Just condition
                    , replyToWatch = False
                  }
                , Cmd.batch
                    [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius info.temperatureC))
                    , CompanionPhone.sendPhoneToWatch (ProvideCondition condition)
                    ]
                )

        GotWeather (Err error) ->
            if not model.replyToWatch then
                ( addError error model, Cmd.none )

            else
                ( { model | lastResponse = 0, lastCondition = Nothing, replyToWatch = False }
                    |> addError error
                , Cmd.batch
                    [ CompanionPhone.sendPhoneToWatch (ProvideTemperature (Celsius 0))
                    , CompanionPhone.sendPhoneToWatch (ProvideCondition Clear)
                    ]
                )

        GotWeather (Ok _) ->
            ( model, Cmd.none )


refreshWeather : Cmd Msg
refreshWeather =
    Weather.current (GotWeather << Result.map Weather.Current)


addError : String -> Model -> Model
addError error model =
    { model | errors = model.errors ++ [ error ] }


toProtocolCondition : Weather.Condition -> WeatherCondition
toProtocolCondition condition =
    case condition of
        Weather.Clear ->
            Clear

        Weather.Cloudy ->
            Cloudy

        Weather.Fog ->
            Fog

        Weather.Drizzle ->
            Drizzle

        Weather.Rain ->
            Rain

        Weather.Snow ->
            Snow

        Weather.Showers ->
            Showers

        Weather.Storm ->
            Storm

        Weather.UnknownWeather ->
            UnknownWeather


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , Weather.onCurrent (GotWeather << Result.map Weather.Current)
        , Lifecycle.onLifecycle LifecycleChanged
        ]


main : Program Decode.Value Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
