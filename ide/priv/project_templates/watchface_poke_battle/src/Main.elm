module Main exposing (main)

import Battle as Battle exposing (Scene(..))
import Basics
import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Frame as Frame
import Pebble.Health as Health
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.System as System
import Pebble.Time as Time
import Pebble.Ui as Ui
import Pokemon as Pokemon exposing (Player, PlayerSpecies(..))
import Render exposing (FaceModel, render)


type alias Model =
    { screenW : Int
    , screenH : Int
    , displayShape : Platform.DisplayShape
    , layout : Render.Layout
    , now : Maybe Time.CurrentDateTime
    , use24Hour : Bool
    , batteryLevel : Maybe Int
    , stepsToday : Maybe Int
    , healthSupported : Bool
    , stepGoal : Int
    , playerSpecies : PlayerSpecies
    , customName : String
    , showDate : Bool
    , showSteps : Bool
    , player : Player
    , opponent : Pokemon.Opponent
    , opponentPick : Int
    , scene : Scene
    , opponentHealth : Float
    , opponentYOffset : Int
    , animating : Bool
    , battleNonce : Int
    }


type Msg
    = CurrentDateTime Time.CurrentDateTime
    | ClockStyle24h Bool
    | MinuteChanged Int
    | HourChanged Int
    | BatteryLevelChanged Int
    | StepsToday Int
    | HealthSupported Bool
    | FrameTick Frame.Frame
    | SelectPressed
    | UpPressed
    | DownPressed
    | PlayerSettingLoaded Int
    | ShowDateSettingLoaded Int
    | ShowStepsSettingLoaded Int
    | CustomNameLoaded String


storagePlayerKey : Int
storagePlayerKey =
    701


storageShowDateKey : Int
storageShowDateKey =
    702


storageShowStepsKey : Int
storageShowStepsKey =
    703


storageCustomNameKey : Int
storageCustomNameKey =
    704


defaultStepGoal : Int
defaultStepGoal =
    10000


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    let
        screenW =
            context.screen.width

        screenH =
            context.screen.height

        startAnimating =
            context.reason == Platform.LaunchWakeup
    in
    ( { screenW = screenW
      , screenH = screenH
      , displayShape = context.screen.shape
      , layout = Render.layoutFor screenW screenH
      , now = Nothing
      , use24Hour = False
      , batteryLevel = Nothing
      , stepsToday = Nothing
      , healthSupported = False
      , stepGoal = defaultStepGoal
      , playerSpecies = Pokemon.Pikachu
      , customName = ""
      , showDate = False
      , showSteps = False
      , player = Pokemon.playerFromSpecies screenW screenH Pokemon.Pikachu
      , opponent =
            Pokemon.opponentForTier screenW screenH 0 0
      , opponentPick = 0
      , scene =
            if startAnimating then
                Battle.initialScene

            else
                Waiting
      , opponentHealth = 1
      , opponentYOffset = 0
      , animating = startAnimating
      , battleNonce = 0
      }
    , Cmd.batch
        [ Time.currentDateTime CurrentDateTime
        , Time.clockStyle24h ClockStyle24h
        , System.batteryLevel BatteryLevelChanged
        , Health.supported HealthSupported
        , Storage.readInt storagePlayerKey PlayerSettingLoaded
        , Storage.readInt storageShowDateKey ShowDateSettingLoaded
        , Storage.readInt storageShowStepsKey ShowStepsSettingLoaded
        , Storage.readString storageCustomNameKey CustomNameLoaded
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model | now = Just value }, Cmd.none )

        ClockStyle24h value ->
            ( { model | use24Hour = value }, Cmd.none )

        MinuteChanged _ ->
            ( model, refreshSteps model )

        HourChanged _ ->
            ( model, Time.currentDateTime CurrentDateTime )

        BatteryLevelChanged level ->
            ( { model | batteryLevel = Just (Basics.clamp 0 100 level) }, Cmd.none )

        HealthSupported supported ->
            ( { model | healthSupported = supported }
            , if supported then
                  refreshSteps model

              else
                  Cmd.none
            )

        StepsToday steps ->
            let
                tier =
                    Pokemon.stepTierIndex steps model.stepGoal

                pick =
                    opponentPickIndex tier steps model.battleNonce
            in
            ( { model
                | stepsToday = Just steps
                , opponent =
                    if model.scene == Waiting then
                        Pokemon.opponentForTier model.screenW model.screenH tier pick

                    else
                        model.opponent
                , opponentPick = pick
              }
            , Cmd.none
            )

        FrameTick _ ->
            if model.animating then
                advanceAnimation model

            else
                ( model, Cmd.none )

        SelectPressed ->
            startBattle model

        UpPressed ->
            cyclePlayer model

        DownPressed ->
            toggleDisplayOptions model

        PlayerSettingLoaded index ->
            let
                species =
                    Pokemon.playerSpeciesFromIndex index

                player =
                    Pokemon.playerFromSpecies model.screenW model.screenH species
            in
            ( { model
                | playerSpecies = species
                , player = withCustomName model.customName player
              }
            , Cmd.none
            )

        ShowDateSettingLoaded value ->
            ( { model | showDate = value /= 0 }, Cmd.none )

        ShowStepsSettingLoaded value ->
            ( { model | showSteps = value /= 0 }, Cmd.none )

        CustomNameLoaded name ->
            ( { model | customName = name, player = withCustomName name model.player }
            , Cmd.none
            )


withCustomName : String -> Player -> Player
withCustomName name player =
    if String.isEmpty name then
        player

    else
        { player | displayName = String.left 8 name }


toggleDisplayOptions : Model -> ( Model, Cmd Msg )
toggleDisplayOptions model =
    case ( model.showDate, model.showSteps ) of
        ( False, False ) ->
            ( { model | showDate = True }, Storage.writeInt storageShowDateKey 1 )

        ( True, False ) ->
            ( { model | showDate = False, showSteps = True }
            , Cmd.batch
                [ Storage.writeInt storageShowDateKey 0
                , Storage.writeInt storageShowStepsKey 1
                ]
            )

        ( _, True ) ->
            ( { model | showDate = False, showSteps = False }
            , Storage.writeInt storageShowStepsKey 0
            )


cyclePlayer : Model -> ( Model, Cmd Msg )
cyclePlayer model =
    let
        nextIndex =
            modBy 5 (playerIndex model.playerSpecies + 1)

        species =
            Pokemon.playerSpeciesFromIndex nextIndex

        player =
            Pokemon.playerFromSpecies model.screenW model.screenH species
                |> withCustomName model.customName
    in
    ( { model | playerSpecies = species, player = player }
    , Storage.writeInt storagePlayerKey nextIndex
    )


playerIndex : PlayerSpecies -> Int
playerIndex species =
    case species of
        Pokemon.Pikachu ->
            0

        Pokemon.PlayerSquirtle ->
            1

        Pokemon.Flareon ->
            2

        Pokemon.Mew ->
            3

        Pokemon.Mewtwo ->
            4


startBattle : Model -> ( Model, Cmd Msg )
startBattle model =
    let
        steps =
            Maybe.withDefault 0 model.stepsToday

        tier =
            Pokemon.stepTierIndex steps model.stepGoal

        nonce =
            model.battleNonce + 1

        pick =
            opponentPickIndex tier steps nonce
    in
    ( { model
        | animating = True
        , scene = Battle.initialScene
        , opponentHealth = 1
        , opponentYOffset = 0
        , opponent = Pokemon.opponentForTier model.screenW model.screenH tier pick
        , opponentPick = pick
        , battleNonce = nonce
      }
    , Cmd.none
    )


{-| Picks a roster index within the current tier. Uses step count and a battle
counter so opponent variety does not depend on `Random.step` (unsupported on watch).
-}
opponentPickIndex : Int -> Int -> Int -> Int
opponentPickIndex tier steps nonce =
    let
        tierSize =
            case tier of
                0 ->
                    3

                3 ->
                    1

                _ ->
                    2
    in
    modBy tierSize (steps + nonce * 17 + tier * 31)


advanceAnimation : Model -> ( Model, Cmd Msg )
advanceAnimation model =
    case model.scene of
        HealthDrain ->
            let
                nextHealth =
                    model.opponentHealth - 0.2
            in
            if nextHealth > 0.1 then
                ( { model | opponentHealth = nextHealth }, Cmd.none )

            else
                advanceFrom model { model | opponentHealth = nextHealth }

        FaintSlide ->
            let
                nextOffset =
                    model.opponentYOffset + 20
            in
            if nextOffset < 100 then
                ( { model | opponentYOffset = nextOffset }, Cmd.none )

            else
                advanceFrom model { model | opponentYOffset = nextOffset }

        _ ->
            advanceFrom model model


advanceFrom : Model -> Model -> ( Model, Cmd Msg )
advanceFrom model nextModel =
    let
        ( scene, finished ) =
            Battle.advance model.scene
                { opponentHealth = nextModel.opponentHealth
                , opponentYOffset = nextModel.opponentYOffset
                }
    in
    if finished then
        ( { nextModel | animating = False, scene = Waiting, opponentHealth = 1, opponentYOffset = 0 }
        , Cmd.none
        )

    else if isFaintedScene scene then
        ( { nextModel | scene = scene, opponentYOffset = 0, opponentHealth = 1 }, Cmd.none )

    else
        ( { nextModel | scene = scene }, Cmd.none )


isFaintedScene : Scene -> Bool
isFaintedScene battleScene =
    case battleScene of
        Fainted _ ->
            True

        _ ->
            False


refreshSteps : Model -> Cmd Msg
refreshSteps model =
    if model.healthSupported then
        Health.sumToday Health.StepCount StepsToday

    else
        Cmd.none


subscriptions : Model -> Sub Msg
subscriptions model =
    Events.batch
        [ Events.onMinuteChange MinuteChanged
        , Events.onHourChange HourChanged
        , System.onBatteryChange BatteryLevelChanged
        , Button.onRelease Button.Select SelectPressed
        , Button.onRelease Button.Up UpPressed
        , Button.onRelease Button.Down DownPressed
        ]
        |> addAnimationSub model


addAnimationSub : Model -> Sub Msg -> Sub Msg
addAnimationSub model subs =
    if model.animating then
        Sub.batch [ subs, Frame.every 500 FrameTick ]

    else
        subs


clockHour : Model -> Int
clockHour model =
    case model.now of
        Just now ->
            now.hour

        Nothing ->
            0


clockMinute : Model -> Int
clockMinute model =
    case model.now of
        Just now ->
            now.minute

        Nothing ->
            0


clockMonth : Model -> Int
clockMonth model =
    case model.now of
        Just now ->
            now.month

        Nothing ->
            1


clockDay : Model -> Int
clockDay model =
    case model.now of
        Just now ->
            now.day

        Nothing ->
            1


playerLevelFromSteps : Model -> Int
playerLevelFromSteps model =
    model.stepsToday
        |> Maybe.map (\steps -> Basics.clamp 4 99 ((steps * 99) // max 1 model.stepGoal))
        |> Maybe.withDefault 4


playerForView : Model -> Pokemon.Player
playerForView model =
    { model.player | levelTag = ":L" ++ String.fromInt (playerLevelFromSteps model) }


thunderFlashForView : Model -> Bool
thunderFlashForView model =
    let
        player =
            playerForView model
    in
    model.scene == AttackFrame2 && player.attack == Pokemon.Thunder


        faceModelFrom : Model -> FaceModel


faceModelFrom model =
    { layout = model.layout
    , scene = model.scene
    , player = playerForView model
    , opponent = model.opponent
    , opponentHealth = model.opponentHealth
    , opponentYOffset = model.opponentYOffset
    , batteryPercent = Maybe.withDefault 100 model.batteryLevel
    , showDate = model.showDate
    , showSteps = model.showSteps
    , stepsToday = model.stepsToday
    , hour = clockHour model
    , minute = clockMinute model
    , month = clockMonth model
    , day = clockDay model
    , use24Hour = model.use24Hour
    , thunderFlash = thunderFlashForView model
    }


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode (render (faceModelFrom model))


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
