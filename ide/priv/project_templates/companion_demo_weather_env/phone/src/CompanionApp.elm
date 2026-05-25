module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..), WeatherCondition(..))
import Pebble.Companion.Environment as Environment
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Weather as Weather
import Platform


type alias Model =
    { temperatureC : Int
    , condition : WeatherCondition
    , sunriseMin : Int
    , sunsetMin : Int
    , moonPhaseE6 : Int
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotWeather (Result String Weather.WeatherUpdate)
    | GotEnvironment (Result String Environment.EnvironmentInfo)


init : () -> ( Model, Cmd Msg )
init _ =
    ( emptyModel, refreshAll )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestWeatherEnv) ->
            ( model, refreshAll )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotWeather (Ok (Weather.Current info)) ->
            let
                condition =
                    toProtocolCondition info.condition
            in
            ( { model | temperatureC = info.temperatureC, condition = condition }
            , Phone.sendPhoneToWatch (ProvideWeather info.temperatureC condition)
            )

        GotWeather _ ->
            ( model, Cmd.none )

        GotEnvironment (Ok info) ->
            let
                sun =
                    info.sun

                moon =
                    info.moon
            in
            ( { model
                | sunriseMin = Maybe.map .sunriseMin sun |> Maybe.withDefault 0
                , sunsetMin = Maybe.map .sunsetMin sun |> Maybe.withDefault 0
                , moonPhaseE6 = Maybe.map .phaseE6 moon |> Maybe.withDefault 0
              }
            , Phone.sendPhoneToWatch
                (ProvideEnvironment
                    (Maybe.map .sunriseMin sun |> Maybe.withDefault 0)
                    (Maybe.map .sunsetMin sun |> Maybe.withDefault 0)
                    (Maybe.map .phaseE6 moon |> Maybe.withDefault 0)
                )
            )

        GotEnvironment (Err _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Weather.onWeather GotWeather
        , Environment.onEnvironment GotEnvironment
        ]


main : Platform.Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


emptyModel : Model
emptyModel =
    { temperatureC = 0
    , condition = UnknownWeather
    , sunriseMin = 0
    , sunsetMin = 0
    , moonPhaseE6 = 0
    }


refreshAll : Cmd Msg
refreshAll =
    Cmd.batch
        [ Environment.setup
        , Weather.current (GotWeather << Result.map Weather.Current)
        , Environment.current GotEnvironment
        ]


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
