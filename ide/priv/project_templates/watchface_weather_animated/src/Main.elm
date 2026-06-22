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
    , activeAnimation : Maybe ActiveAnimation
    , nextAnimationId : Int
    , suppressWeatherTransitions : Bool
    , warmupTicksRemaining : Int
    , screenW : Int
    , screenH : Int
    }


type alias ActiveAnimation =
    { id : Ui.AnimationId
    , vector : Resources.AnimatedVector
    }


type Msg
    = CurrentDateTime Time.CurrentDateTime
    | FromPhone PhoneToWatch
    | MinuteChanged Int
    | SecondElapsed
    | AnimationFinished Ui.AnimationId
    | EnableWeatherTransitions


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { now = Nothing
      , temperature = Nothing
      , condition = Nothing
      , displayedCondition = Nothing
      , activeAnimation = Nothing
      , nextAnimationId = 1
      , suppressWeatherTransitions = True
      , warmupTicksRemaining = msToWholeSeconds weatherTransitionWarmupMs
      , screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.batch
        [ Time.currentDateTime CurrentDateTime
        , CompanionWatch.sendWatchToPhone (RequestWeather CurrentLocation)
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

        SecondElapsed ->
            if model.warmupTicksRemaining > 0 then
                let
                    next =
                        model.warmupTicksRemaining - 1
                in
                if next == 0 then
                    update EnableWeatherTransitions { model | warmupTicksRemaining = 0 }

                else
                    ( { model | warmupTicksRemaining = next }, Cmd.none )

            else
                ( model, Cmd.none )

        AnimationFinished finishedId ->
            case model.activeAnimation of
                Just animation ->
                    if animation.id == finishedId then
                        ( { model
                            | displayedCondition = model.condition
                            , activeAnimation = Nothing
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

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

                    else if model.suppressWeatherTransitions || model.activeAnimation /= Nothing then
                        ( { nextModel | displayedCondition = Just newCondition, activeAnimation = Nothing }
                        , Cmd.none
                        )

                    else
                        case transitionVector displayed newCondition of
                            Nothing ->
                                ( { nextModel | displayedCondition = Just newCondition }, Cmd.none )

                            Just vector ->
                                let
                                    animationId =
                                        Ui.AnimationId model.nextAnimationId
                                in
                                ( { nextModel
                                    | activeAnimation =
                                        Just { id = animationId, vector = vector }
                                    , nextAnimationId = model.nextAnimationId + 1
                                  }
                                , Cmd.none
                                )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Events.onSecondChange (\_ -> SecondElapsed)
        , Events.onAnimationFinished AnimationFinished
        , Events.onMinuteChange MinuteChanged
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
                case model.activeAnimation of
                    Just animation ->
                        [ Ui.drawVectorSequenceAt animation.id animation.vector origin ]

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


conditionVector : WeatherCondition -> Resources.StaticVector
conditionVector condition =
    case condition of
        Clear ->
            Resources.VectorStaticWeatherClear

        Cloudy ->
            Resources.VectorStaticWeatherCloudy

        Fog ->
            Resources.VectorStaticWeatherFog

        Drizzle ->
            Resources.VectorStaticWeatherDrizzle

        Rain ->
            Resources.VectorStaticWeatherRain

        Snow ->
            Resources.VectorStaticWeatherSnow

        Showers ->
            Resources.VectorStaticWeatherShowers

        Storm ->
            Resources.VectorStaticWeatherStorm

        UnknownWeather ->
            Resources.VectorStaticWeatherUnknown


transitionVector : WeatherCondition -> WeatherCondition -> Maybe Resources.AnimatedVector
transitionVector from to =
    if from == to then
        Nothing

    else
        case from of
            Clear ->
                case to of
                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionClearToCloudy

                    Fog ->
                        Just Resources.VectorAnimatedTransitionClearToFog

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionClearToDrizzle

                    Rain ->
                        Just Resources.VectorAnimatedTransitionClearToRain

                    Snow ->
                        Just Resources.VectorAnimatedTransitionClearToSnow

                    Showers ->
                        Just Resources.VectorAnimatedTransitionClearToShowers

                    Storm ->
                        Just Resources.VectorAnimatedTransitionClearToStorm

                    _ ->
                        Nothing

            Cloudy ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionCloudyToClear

                    Fog ->
                        Just Resources.VectorAnimatedTransitionCloudyToFog

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionCloudyToDrizzle

                    Rain ->
                        Just Resources.VectorAnimatedTransitionCloudyToRain

                    Snow ->
                        Just Resources.VectorAnimatedTransitionCloudyToSnow

                    Showers ->
                        Just Resources.VectorAnimatedTransitionCloudyToShowers

                    Storm ->
                        Just Resources.VectorAnimatedTransitionCloudyToStorm

                    _ ->
                        Nothing

            Fog ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionFogToClear

                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionFogToCloudy

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionFogToDrizzle

                    Rain ->
                        Just Resources.VectorAnimatedTransitionFogToRain

                    Snow ->
                        Just Resources.VectorAnimatedTransitionFogToSnow

                    Showers ->
                        Just Resources.VectorAnimatedTransitionFogToShowers

                    Storm ->
                        Just Resources.VectorAnimatedTransitionFogToStorm

                    _ ->
                        Nothing

            Drizzle ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionDrizzleToClear

                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionDrizzleToCloudy

                    Fog ->
                        Just Resources.VectorAnimatedTransitionDrizzleToFog

                    Rain ->
                        Just Resources.VectorAnimatedTransitionDrizzleToRain

                    Snow ->
                        Just Resources.VectorAnimatedTransitionDrizzleToSnow

                    Showers ->
                        Just Resources.VectorAnimatedTransitionDrizzleToShowers

                    Storm ->
                        Just Resources.VectorAnimatedTransitionDrizzleToStorm

                    _ ->
                        Nothing

            Rain ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionRainToClear

                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionRainToCloudy

                    Fog ->
                        Just Resources.VectorAnimatedTransitionRainToFog

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionRainToDrizzle

                    Snow ->
                        Just Resources.VectorAnimatedTransitionRainToSnow

                    Showers ->
                        Just Resources.VectorAnimatedTransitionRainToShowers

                    Storm ->
                        Just Resources.VectorAnimatedTransitionRainToStorm

                    _ ->
                        Nothing

            Snow ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionSnowToClear

                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionSnowToCloudy

                    Fog ->
                        Just Resources.VectorAnimatedTransitionSnowToFog

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionSnowToDrizzle

                    Rain ->
                        Just Resources.VectorAnimatedTransitionSnowToRain

                    Showers ->
                        Just Resources.VectorAnimatedTransitionSnowToShowers

                    Storm ->
                        Just Resources.VectorAnimatedTransitionSnowToStorm

                    _ ->
                        Nothing

            Showers ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionShowersToClear

                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionShowersToCloudy

                    Fog ->
                        Just Resources.VectorAnimatedTransitionShowersToFog

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionShowersToDrizzle

                    Rain ->
                        Just Resources.VectorAnimatedTransitionShowersToRain

                    Snow ->
                        Just Resources.VectorAnimatedTransitionShowersToSnow

                    Storm ->
                        Just Resources.VectorAnimatedTransitionShowersToStorm

                    _ ->
                        Nothing

            Storm ->
                case to of
                    Clear ->
                        Just Resources.VectorAnimatedTransitionStormToClear

                    Cloudy ->
                        Just Resources.VectorAnimatedTransitionStormToCloudy

                    Fog ->
                        Just Resources.VectorAnimatedTransitionStormToFog

                    Drizzle ->
                        Just Resources.VectorAnimatedTransitionStormToDrizzle

                    Rain ->
                        Just Resources.VectorAnimatedTransitionStormToRain

                    Snow ->
                        Just Resources.VectorAnimatedTransitionStormToSnow

                    Showers ->
                        Just Resources.VectorAnimatedTransitionStormToShowers

                    _ ->
                        Nothing

            UnknownWeather ->
                Nothing


iconSize : Int
iconSize =
    48


weatherTransitionWarmupMs : Int
weatherTransitionWarmupMs =
    2500


msToWholeSeconds : Int -> Int
msToWholeSeconds ms =
    (ms + 999) // 1000


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
