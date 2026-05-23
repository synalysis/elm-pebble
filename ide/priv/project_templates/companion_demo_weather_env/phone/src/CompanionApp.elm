module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Pebble.Companion as Companion
import Pebble.Companion.Environment as Environment
import Pebble.Companion.Phone as Phone
import Pebble.Companion.Weather as Weather
import Platform


type alias Model =
    { temperatureC : Int
    , conditionCode : Int
    , sunriseMin : Int
    , sunsetMin : Int
    , moonPhaseE6 : Int
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotWeather (Result String Weather.WeatherUpdate)
    | GotEnvironment (Result String Environment.EnvironmentInfo)


init : Platform.Flags -> ( Model, Cmd Msg )
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
            ( { model | temperatureC = info.temperatureC, conditionCode = conditionCode info.condition }
            , Phone.sendPhoneToWatch (ProvideWeather info.temperatureC (conditionCode info.condition))
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
        , Companion.batch
            [ Weather.part GotWeather
            , Environment.part GotEnvironment
            ]
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
    { temperatureC = 0
    , conditionCode = 0
    , sunriseMin = 0
    , sunsetMin = 0
    , moonPhaseE6 = 0
    }


refreshAll : Cmd Msg
refreshAll =
    Cmd.batch
        [ Weather.current (GotWeather << Result.map Weather.Current)
        , Environment.current GotEnvironment
        ]


conditionCode : Weather.Condition -> Int
conditionCode condition =
    case condition of
        Weather.Clear ->
            0

        Weather.Cloudy ->
            1

        Weather.Fog ->
            2

        Weather.Drizzle ->
            3

        Weather.Rain ->
            4

        Weather.Snow ->
            5

        Weather.Showers ->
            6

        Weather.Storm ->
            7

        Weather.UnknownWeather ->
            8
