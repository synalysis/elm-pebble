module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Frame as Frame
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.Vibes as Vibes


type alias PlatformTile =
    { slot : Int
    , baseY : Int
    , moving : Bool
    }


type alias Obstacle =
    { slot : Int
    , y : Int
    , w : Int
    , h : Int
    }


type alias Model =
    { playerY : Int
    , velocityY : Int
    , offset : Int
    , score : Int
    , best : Int
    , alive : Bool
    , lastLandingSlot : Maybe Int
    , screenW : Int
    , screenH : Int
    , displayShape : Platform.DisplayShape
    }


type Msg
    = FrameTick Frame.Frame
    | UpPressed
    | DownPressed
    | BestScoreLoaded Int


playerW : Int
playerW =
    12


playerH : Int
playerH =
    14


playerX : Int
playerX =
    24


tileSpacing : Int
tileSpacing =
    48


storageKey : Int
storageKey =
    201


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( freshModel 0 context.screen.width context.screen.height context.screen.shape
    , Storage.readInt storageKey BestScoreLoaded
    )


freshModel : Int -> Int -> Int -> Platform.DisplayShape -> Model
freshModel best screenW screenH displayShape =
    { playerY = 84
    , velocityY = 0
    , offset = 0
    , score = 0
    , best = best
    , alive = True
    , lastLandingSlot = Nothing
    , screenW = screenW
    , screenH = screenH
    , displayShape = displayShape
    }


reset : Model -> Model
reset model =
    freshModel model.best model.screenW model.screenH model.displayShape


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FrameTick _ ->
            if model.alive then
                step model

            else
                ( model, Cmd.none )

        UpPressed ->
            if model.alive then
                ( { model | velocityY = -9 }, Cmd.none )

            else
                ( reset model, Cmd.none )

        DownPressed ->
            if model.alive then
                ( { model | velocityY = min 12 (model.velocityY + 3) }, Cmd.none )

            else
                ( model, Cmd.none )

        BestScoreLoaded value ->
            ( { model | best = max 0 value }, Cmd.none )


step : Model -> ( Model, Cmd Msg )
step model =
    let
        scrollSpeed =
            min 8 (3 + model.score // 120)

        nextOffset =
            model.offset + scrollSpeed

        nextY =
            model.playerY + model.velocityY

        player =
            { x = playerX, y = nextY, w = playerW, h = playerH }

        tiles =
            visibleTiles nextOffset

        obstacles =
            visibleObstacles nextOffset

        landingTile =
            if model.velocityY >= 0 then
                tiles
                    |> List.filter (landedOnTile nextOffset model.playerY player)
                    |> List.sortBy
                        (\tile ->
                            let
                                rect =
                                    platformRect nextOffset tile
                            in
                            rect.y
                        )
                    |> List.head

            else
                Nothing

        fixedY =
            case landingTile of
                Just tile ->
                    let
                        rect =
                            platformRect nextOffset tile
                    in
                    rect.y - playerH

                Nothing ->
                    nextY

        landedPlayer =
            { x = playerX, y = fixedY, w = playerW, h = playerH }

        scoreGain =
            landingScore model.lastLandingSlot landingTile

        nextScore =
            model.score + scoreGain

        nextBest =
            max model.best nextScore

        obstacleHit =
            List.any (obstacleCollision landedPlayer nextOffset) obstacles

        fellOff =
            fixedY + playerH >= 156 && landingTile == Nothing

        dead =
            obstacleHit || fellOff

        landCmd =
            if scoreGain > 0 then
                Vibes.shortPulse

            else
                Cmd.none

        persistCmd =
            if nextBest > model.best || dead then
                Storage.writeInt storageKey nextBest

            else
                Cmd.none

        deathCmd =
            if dead then
                Vibes.doublePulse

            else
                Cmd.none
    in
    ( { model
        | offset = nextOffset
        , playerY = fixedY
        , velocityY =
            if landingTile /= Nothing then
                0

            else
                min 9 (model.velocityY + 1)
        , score = nextScore
        , best = nextBest
        , alive = not dead
        , lastLandingSlot =
            case landingTile of
                Just tile ->
                    Just tile.slot

                Nothing ->
                    model.lastLandingSlot
      }
    , Cmd.batch [ persistCmd, if dead then deathCmd else landCmd ]
    )


landingScore : Maybe Int -> Maybe PlatformTile -> Int
landingScore lastLanding landingTile =
    case landingTile of
        Nothing ->
            0

        Just tile ->
            if lastLanding == Just tile.slot then
                0

            else if tile.moving then
                2

            else
                1


visibleSlots : Int -> List Int
visibleSlots offset =
    let
        first =
            offset // tileSpacing - 1

        last =
            first + 6
    in
    List.range first last


visibleTiles : Int -> List PlatformTile
visibleTiles offset =
    visibleSlots offset
        |> List.concatMap genPlatforms


visibleObstacles : Int -> List Obstacle
visibleObstacles offset =
    visibleSlots offset
        |> List.filterMap genObstacle


genPlatforms : Int -> List PlatformTile
genPlatforms slot =
    let
        roll =
            hash slot
    in
    if slot <= 0 then
        [ { slot = slot, baseY = 132, moving = False } ]

    else if modBy 6 roll == 0 then
        []

    else
        [ { slot = slot
          , baseY = if modBy 9 roll == 0 then 116 else 132
          , moving = modBy 8 roll == 0 && slot > 2
          }
        ]


genObstacle : Int -> Maybe Obstacle
genObstacle slot =
    let
        roll =
            hash (slot * 31 + 5)
    in
    if slot < 4 then
        Nothing

    else if modBy 10 roll == 0 then
        Just { slot = slot, y = 98, w = 18, h = 28 }

    else
        Nothing


hash : Int -> Int
hash n =
    modBy 997 (n * 73 + 17)


landedOnTile : Int -> Int -> { x : Int, y : Int, w : Int, h : Int } -> PlatformTile -> Bool
landedOnTile offset previousPlayerY player tile =
    let
        platform =
            platformRect offset tile

        previousBottom =
            previousPlayerY + player.h

        playerBottom =
            player.y + player.h

        horizontalOverlap =
            player.x < platform.x + platform.w && player.x + player.w > platform.x

        landingFromAbove =
            previousBottom <= platform.y && playerBottom >= platform.y

        ridingPlatform =
            abs (previousBottom - platform.y) <= 12
    in
    horizontalOverlap && playerBottom >= platform.y - 1 && (landingFromAbove || ridingPlatform)


        obstacleCollision : { x : Int, y : Int, w : Int, h : Int } -> Int -> Obstacle -> Bool


obstacleCollision player offset obstacle =
    rectsOverlap player (obstacleRect offset obstacle)


rectsOverlap : { x : Int, y : Int, w : Int, h : Int } -> { x : Int, y : Int, w : Int, h : Int } -> Bool
rectsOverlap a b =
    a.x
        < b.x
        + b.w
        && a.x
        + a.w
        > b.x
        && a.y
        < b.y
        + b.h
        && a.y
        + a.h
        > b.y


obstacleRect : Int -> Obstacle -> { x : Int, y : Int, w : Int, h : Int }
obstacleRect offset obstacle =
    { x = obstacle.slot * tileSpacing - offset + 12
    , y = obstacle.y
    , w = obstacle.w
    , h = obstacle.h
    }


platformRect : Int -> PlatformTile -> { x : Int, y : Int, w : Int, h : Int }
platformRect offset tile =
    let
        bob =
            if tile.moving then
                9 - abs (modBy 18 offset - 9)

            else
                0
    in
    { x = tile.slot * tileSpacing - offset
    , y = tile.baseY + bob
    , w = 40
    , h = 8
    }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Frame.every 33 FrameTick
        , Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    let
        tiles =
            visibleTiles model.offset

        obstacles =
            visibleObstacles model.offset

        hud =
            hudOps model
    in
    Ui.toUiNode
        ([ Ui.clear Color.white ]
            ++ hud
            ++ [ Ui.drawBitmapInRect Resources.BitmapStaticJumpHero { x = playerX, y = model.playerY, w = playerW, h = playerH } ]
            ++ List.map (drawTile model.offset) tiles
            ++ List.map (drawObstacle model.offset) obstacles
            ++ (if model.alive then
                    []

                else
                    gameOverOps model
               )
        )


hudOps : Model -> List Ui.RenderOp
hudOps model =
    let
        textOptions =
            Ui.alignCenter Ui.defaultTextOptions

        textW =
            if Platform.displayShapeIsRound model.displayShape then
                (min model.screenW model.screenH * 4) // 9

            else
                model.screenW - 8

        textX =
            (model.screenW - textW) // 2
    in
    [ Ui.text Resources.DefaultFont textOptions { x = textX, y = 10, w = textW, h = 16 } ("Score " ++ String.fromInt model.score)
    , Ui.text Resources.DefaultFont textOptions { x = textX, y = 26, w = textW, h = 16 } ("Best " ++ String.fromInt model.best)
    ]


gameOverOps : Model -> List Ui.RenderOp
gameOverOps model =
    let
        textOptions =
            Ui.alignCenter Ui.defaultTextOptions

        textW =
            if Platform.displayShapeIsRound model.displayShape then
                (min model.screenW model.screenH * 4) // 9

            else
                model.screenW - 8

        textX =
            (model.screenW - textW) // 2

        textY =
            if Platform.displayShapeIsRound model.displayShape then
                (min model.screenW model.screenH * 3 // 5) - 14

            else
                model.screenH - 24
    in
    [ Ui.text Resources.DefaultFont textOptions { x = textX, y = textY, w = textW, h = 28 } "Press Up" ]


toUiRect : { x : Int, y : Int, w : Int, h : Int } -> { x : Int, y : Int, w : Int, h : Int }
toUiRect rect =
    rect


drawTile : Int -> PlatformTile -> Ui.RenderOp
drawTile offset tile =
    Ui.fillRect (toUiRect (platformRect offset tile)) (tileColor tile)


tileColor : PlatformTile -> Color
tileColor tile =
    if tile.moving then
        Color.darkGray

    else
        Color.black


drawObstacle : Int -> Obstacle -> Ui.RenderOp
drawObstacle offset obstacle =
    Ui.fillRect (toUiRect (obstacleRect offset obstacle)) Color.black


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
