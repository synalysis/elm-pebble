module Main exposing (main)

import Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), WatchToPhone(..), WeatherCondition(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Cmd as Cmd
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Time as Time
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { now : Maybe Time.CurrentDateTime
    , temperature : Maybe Temperature
    , condition : Maybe WeatherCondition
    , displayedCondition : Maybe WeatherCondition
    , activeTransition : Maybe Resources.VectorGraphic
    , suppressWeatherTransitions : Bool
    , screenW : Int
    , screenH : Int
    }


type Msg
    = CurrentDateTime Time.CurrentDateTime
    | FromPhone PhoneToWatch
    | MinuteChanged Int
    | TransitionFinished
    | EnableWeatherTransitions


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { now = Nothing
      , temperature = Nothing
      , condition = Nothing
      , displayedCondition = Nothing
      , activeTransition = Nothing
      , suppressWeatherTransitions = True
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.batch
        [ Time.currentDateTime CurrentDateTime
        , CompanionWatch.sendWatchToPhone (RequestWeather CurrentLocation)
        , Cmd.timerAfter weatherTransitionWarmupMs EnableWeatherTransitions
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model | now = Just value }, Cmd.none )

        FromPhone message ->
            updateFromPhone message model

        MinuteChanged _ ->
            ( model
            , Cmd.batch
                [ Time.currentDateTime CurrentDateTime
                , CompanionWatch.sendWatchToPhone (RequestWeather CurrentLocation)
                ]
            )

        TransitionFinished ->
            ( { model
                | displayedCondition = model.condition
                , activeTransition = Nothing
              }
            , Cmd.none
            )

        EnableWeatherTransitions ->
            ( { model | suppressWeatherTransitions = False }, Cmd.none )


updateFromPhone : PhoneToWatch -> Model -> ( Model, Cmd Msg )
updateFromPhone message model =
    case message of
        ProvideTemperature temperature ->
            ( { model | temperature = Just temperature }, Cmd.none )

        ProvideCondition newCondition ->
            let
                nextModel =
                    { model | condition = Just newCondition }
            in
            case model.displayedCondition of
                Nothing ->
                    ( { nextModel | displayedCondition = Just newCondition }, Cmd.none )

                Just displayed ->
                    if newCondition == displayed then
                        ( nextModel, Cmd.none )

                    else if model.suppressWeatherTransitions || model.activeTransition /= Nothing then
                        ( { nextModel | displayedCondition = Just newCondition, activeTransition = Nothing }
                        , Cmd.none
                        )

                    else
                        case transitionVector displayed newCondition of
                            Nothing ->
                                ( { nextModel | displayedCondition = Just newCondition }, Cmd.none )

                            Just vector ->
                                ( { nextModel | activeTransition = Just vector }
                                , Cmd.timerAfter transitionDurationMs TransitionFinished
                                )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Events.onMinuteChange MinuteChanged
        , CompanionWatch.onPhoneToWatch FromPhone
        ]


view : Model -> Ui.UiNode
view model =
    let
        cx =
            model.screenW // 2

        timeY =
            (model.screenH // 2) - 28

        iconOrigin =
            { x = cx - (iconSize // 2), y = (model.screenH * 3) // 4 - (iconSize // 2) }
    in
    [ Ui.clear Color.white
    , drawCentered model Color.black timeY 40 (timeString model)
    , drawCentered model Color.black (timeY + 36) 18 (weatherString model)
    ]
        ++ weatherIconOps model iconOrigin
        |> Ui.toUiNode


weatherIconOps : Model -> Ui.Point -> List Ui.RenderOp
weatherIconOps model origin =
    if model.suppressWeatherTransitions then
        []

    else
        case ( model.temperature, model.condition ) of
            ( Just _, Just _ ) ->
                case model.activeTransition of
                    Just vector ->
                        [ Ui.drawVectorSequenceAt vector origin ]

                    Nothing ->
                        case model.displayedCondition of
                            Nothing ->
                                []

                            Just condition ->
                                [ Ui.drawVectorAt (conditionVector condition) origin ]

            _ ->
                []


drawCentered : Model -> Color.Color -> Int -> Int -> String -> Ui.RenderOp
drawCentered model textColor y height value =
    Ui.group
        (Ui.context
            [ Ui.textColor textColor ]
            [ Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = 0, y = y, w = model.screenW, h = height } value ]
        )


timeString : Model -> String
timeString model =
    case model.now of
        Nothing ->
            "--:--"

        Just currentDateTime ->
            pad2 currentDateTime.hour ++ ":" ++ pad2 currentDateTime.minute


weatherString : Model -> String
weatherString model =
    case ( model.temperature, model.condition ) of
        ( Just temperature, Just condition ) ->
            temperatureString temperature ++ " " ++ conditionString condition

        _ ->
            "Loading..."


temperatureString : Temperature -> String
temperatureString temperature =
    case temperature of
        Celsius value ->
            String.fromInt value ++ "C"

        Fahrenheit value ->
            String.fromInt value ++ "F"


conditionString : WeatherCondition -> String
conditionString condition =
    case condition of
        Clear ->
            "Clear"

        Cloudy ->
            "Cloudy"

        Fog ->
            "Fog"

        Drizzle ->
            "Drizzle"

        Rain ->
            "Rain"

        Snow ->
            "Snow"

        Showers ->
            "Showers"

        Storm ->
            "Storm"

        UnknownWeather ->
            "Weather"


conditionVector : WeatherCondition -> Resources.VectorGraphic
conditionVector condition =
    case condition of
        Clear ->
            Resources.WeatherClear

        Cloudy ->
            Resources.WeatherCloudy

        Fog ->
            Resources.WeatherFog

        Drizzle ->
            Resources.WeatherDrizzle

        Rain ->
            Resources.WeatherRain

        Snow ->
            Resources.WeatherSnow

        Showers ->
            Resources.WeatherShowers

        Storm ->
            Resources.WeatherStorm

        UnknownWeather ->
            Resources.WeatherUnknown


transitionVector : WeatherCondition -> WeatherCondition -> Maybe Resources.VectorGraphic
transitionVector from to =
    if from == to then
        Nothing

    else
        case from of
            Clear ->
                case to of
                    Cloudy ->
                        Just Resources.TransitionClearToCloudy

                    Fog ->
                        Just Resources.TransitionClearToFog

                    Drizzle ->
                        Just Resources.TransitionClearToDrizzle

                    Rain ->
                        Just Resources.TransitionClearToRain

                    Snow ->
                        Just Resources.TransitionClearToSnow

                    Showers ->
                        Just Resources.TransitionClearToShowers

                    Storm ->
                        Just Resources.TransitionClearToStorm

                    _ ->
                        Nothing

            Cloudy ->
                case to of
                    Clear ->
                        Just Resources.TransitionCloudyToClear

                    Fog ->
                        Just Resources.TransitionCloudyToFog

                    Drizzle ->
                        Just Resources.TransitionCloudyToDrizzle

                    Rain ->
                        Just Resources.TransitionCloudyToRain

                    Snow ->
                        Just Resources.TransitionCloudyToSnow

                    Showers ->
                        Just Resources.TransitionCloudyToShowers

                    Storm ->
                        Just Resources.TransitionCloudyToStorm

                    _ ->
                        Nothing

            Fog ->
                case to of
                    Clear ->
                        Just Resources.TransitionFogToClear

                    Cloudy ->
                        Just Resources.TransitionFogToCloudy

                    Drizzle ->
                        Just Resources.TransitionFogToDrizzle

                    Rain ->
                        Just Resources.TransitionFogToRain

                    Snow ->
                        Just Resources.TransitionFogToSnow

                    Showers ->
                        Just Resources.TransitionFogToShowers

                    Storm ->
                        Just Resources.TransitionFogToStorm

                    _ ->
                        Nothing

            Drizzle ->
                case to of
                    Clear ->
                        Just Resources.TransitionDrizzleToClear

                    Cloudy ->
                        Just Resources.TransitionDrizzleToCloudy

                    Fog ->
                        Just Resources.TransitionDrizzleToFog

                    Rain ->
                        Just Resources.TransitionDrizzleToRain

                    Snow ->
                        Just Resources.TransitionDrizzleToSnow

                    Showers ->
                        Just Resources.TransitionDrizzleToShowers

                    Storm ->
                        Just Resources.TransitionDrizzleToStorm

                    _ ->
                        Nothing

            Rain ->
                case to of
                    Clear ->
                        Just Resources.TransitionRainToClear

                    Cloudy ->
                        Just Resources.TransitionRainToCloudy

                    Fog ->
                        Just Resources.TransitionRainToFog

                    Drizzle ->
                        Just Resources.TransitionRainToDrizzle

                    Snow ->
                        Just Resources.TransitionRainToSnow

                    Showers ->
                        Just Resources.TransitionRainToShowers

                    Storm ->
                        Just Resources.TransitionRainToStorm

                    _ ->
                        Nothing

            Snow ->
                case to of
                    Clear ->
                        Just Resources.TransitionSnowToClear

                    Cloudy ->
                        Just Resources.TransitionSnowToCloudy

                    Fog ->
                        Just Resources.TransitionSnowToFog

                    Drizzle ->
                        Just Resources.TransitionSnowToDrizzle

                    Rain ->
                        Just Resources.TransitionSnowToRain

                    Showers ->
                        Just Resources.TransitionSnowToShowers

                    Storm ->
                        Just Resources.TransitionSnowToStorm

                    _ ->
                        Nothing

            Showers ->
                case to of
                    Clear ->
                        Just Resources.TransitionShowersToClear

                    Cloudy ->
                        Just Resources.TransitionShowersToCloudy

                    Fog ->
                        Just Resources.TransitionShowersToFog

                    Drizzle ->
                        Just Resources.TransitionShowersToDrizzle

                    Rain ->
                        Just Resources.TransitionShowersToRain

                    Snow ->
                        Just Resources.TransitionShowersToSnow

                    Storm ->
                        Just Resources.TransitionShowersToStorm

                    _ ->
                        Nothing

            Storm ->
                case to of
                    Clear ->
                        Just Resources.TransitionStormToClear

                    Cloudy ->
                        Just Resources.TransitionStormToCloudy

                    Fog ->
                        Just Resources.TransitionStormToFog

                    Drizzle ->
                        Just Resources.TransitionStormToDrizzle

                    Rain ->
                        Just Resources.TransitionStormToRain

                    Snow ->
                        Just Resources.TransitionStormToSnow

                    Showers ->
                        Just Resources.TransitionStormToShowers

                    _ ->
                        Nothing

            UnknownWeather ->
                Nothing


iconSize : Int
iconSize =
    48


transitionDurationMs : Int
transitionDurationMs =
    900


weatherTransitionWarmupMs : Int
weatherTransitionWarmupMs =
    2500


pad2 : Int -> String
pad2 value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
