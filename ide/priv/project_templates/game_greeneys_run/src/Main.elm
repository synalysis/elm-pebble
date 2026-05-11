module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Frame as Frame
import Pebble.Game.Collision as Collision
import Pebble.Game.Sprite as Sprite
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias PlatformTile =
    { x : Int
    , y : Int
    , moving : Bool
    }


type alias Model =
    { playerY : Int
    , velocityY : Int
    , offset : Int
    , jumping : Bool
    , paused : Bool
    , score : Int
    , savedScore : Int
    , tiles : List PlatformTile
    }


type Msg
    = FrameTick Frame.Frame
    | UpPressed
    | DownPressed
    | StorageStringLoaded String


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { playerY = 84
      , velocityY = 0
      , offset = 0
      , jumping = False
      , paused = False
      , score = 0
      , savedScore = 0
      , tiles =
            [ { x = 0, y = 132, moving = False }
            , { x = 1, y = 132, moving = False }
            , { x = 2, y = 132, moving = False }
            , { x = 5, y = 116, moving = True }
            , { x = 8, y = 132, moving = False }
            ]
      }
    , Storage.readString 201 StorageStringLoaded
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FrameTick _ ->
            if model.paused then
                ( model, Cmd.none )

            else
                step model

        UpPressed ->
            ( { model | velocityY = -9, jumping = True, paused = False }, Cmd.none )

        DownPressed ->
            ( { model | paused = not model.paused }, Storage.writeString 201 (String.fromInt model.score) )

        StorageStringLoaded value ->
            ( { model | savedScore = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )


step : Model -> ( Model, Cmd Msg )
step model =
    let
        nextOffset =
            model.offset + 3

        nextY =
            min 140 (model.playerY + model.velocityY)

        player =
            { x = 24, y = nextY, w = 12, h = 14 }

        landingTile =
            if model.velocityY >= 0 then
                List.filter (landedOnTile nextOffset (model.playerY + 14) player) model.tiles
                    |> List.head

            else
                Nothing

        fixedY =
            case landingTile of
                Just tile ->
                    (tileRect nextOffset tile).y - player.h

                Nothing ->
                    nextY
    in
    ( { model
        | offset = nextOffset
        , playerY = fixedY
        , velocityY =
            if landingTile /= Nothing then
                0

            else
                min 9 (model.velocityY + 1)
        , jumping = landingTile == Nothing
        , score = model.score + 1
      }
    , Cmd.none
    )


landedOnTile : Int -> Int -> Collision.Rect -> PlatformTile -> Bool
landedOnTile offset previousBottom player tile =
    let
        platform =
            tileRect offset tile
    in
    Collision.rectRect player platform
        && previousBottom
        <= platform.y
        && player.y
        + player.h
        >= platform.y


tileRect : Int -> PlatformTile -> Collision.Rect
tileRect offset tile =
    let
        bob =
            if tile.moving then
                modBy 18 offset - 9

            else
                0
    in
    { x = tile.x * 48 - modBy 384 offset
    , y = tile.y + bob
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
    Ui.toUiNode
        ([ Ui.clear Color.white
         , Ui.drawBitmapInRect Resources.NoBitmap { x = 0, y = 0, w = 1, h = 1 }
         , Ui.text Resources.DefaultFont { x = 4, y = 4, w = 130, h = 20 } ("Run " ++ String.fromInt model.score)
         , Ui.text Resources.DefaultFont { x = 4, y = 24, w = 130, h = 20 } ("Saved " ++ String.fromInt model.savedScore)
         , Ui.fillRect { x = 24, y = model.playerY, w = 12, h = 14 } Color.black
         ]
            ++ Sprite.parallaxBitmap Resources.NoBitmap { x = 0, y = 148, w = 144, h = 16 } (model.offset // 3)
            ++ List.map (drawTile model.offset) model.tiles
            ++ (if model.paused then
                    [ Ui.text Resources.DefaultFont { x = 42, y = 76, w = 80, h = 24 } "PAUSED" ]

                else
                    []
               )
        )


drawTile : Int -> PlatformTile -> Ui.RenderOp
drawTile offset tile =
    Ui.fillRect (tileRect offset tile) Color.black


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
