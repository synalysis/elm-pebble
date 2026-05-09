module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Frame as Frame
import Pebble.Game.Collision as Collision
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Pebble.Vibes as Vibes


type alias Tube =
    { x : Int
    , gapY : Int
    }


type alias Model =
    { birdY : Int
    , velocity : Int
    , tubes : List Tube
    , score : Int
    , best : Int
    , alive : Bool
    }


type Msg
    = FrameTick Frame.Frame
    | UpPressed
    | StorageStringLoaded String


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( reset 0, Storage.readString 42 StorageStringLoaded )


reset : Int -> Model
reset best =
    { birdY = 60
    , velocity = 0
    , tubes = [ { x = 120, gapY = 62 }, { x = 198, gapY = 88 } ]
    , score = 0
    , best = best
    , alive = True
    }


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
                ( { model | velocity = -8 }, Cmd.none )

            else
                ( reset model.best, Cmd.none )

        StorageStringLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )


step : Model -> ( Model, Cmd Msg )
step model =
    let
        movedTubes =
            List.map (\tube -> { tube | x = tube.x - 3 }) model.tubes

        recycled =
            case movedTubes of
                first :: rest ->
                    if first.x < -22 then
                        rest ++ [ { x = 144, gapY = 48 + modBy 64 (model.score * 17) } ]

                    else
                        movedTubes

                [] ->
                    movedTubes

        nextY =
            model.birdY + model.velocity

        nextVelocity =
            min 8 (model.velocity + 1)

        bird =
            { x = 18, y = nextY, w = 14, h = 14 }

        tubeHits =
            List.any (tubeCollision bird) recycled

        dead =
            nextY > 145 || nextY < 0 || tubeHits

        nextScore =
            model.score + 1

        nextBest =
            max model.best nextScore
    in
    ( { model
        | birdY = nextY
        , velocity = nextVelocity
        , tubes = recycled
        , score = nextScore
        , best = nextBest
        , alive = not dead
      }
    , if dead then
        Cmd.batch [ Storage.writeString 42 (String.fromInt nextBest), Vibes.shortPulse ]

      else
        Cmd.none
    )


tubeCollision : Collision.Rect -> Tube -> Bool
tubeCollision bird tube =
    let
        gapH =
            46
    in
    Collision.rectRect bird { x = tube.x, y = 0, w = 22, h = tube.gapY }
        || Collision.rectRect bird { x = tube.x, y = tube.gapY + gapH, w = 22, h = 168 - tube.gapY - gapH }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Frame.every 33 FrameTick
        , Button.onPress Button.Up UpPressed
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        ([ Ui.clear Color.white
         , Ui.drawBitmapInRect Resources.NoBitmap { x = 0, y = 0, w = 1, h = 1 }
         , Ui.fillRect { x = 18, y = model.birdY, w = 14, h = 14 } Color.black
         , Ui.text Resources.DefaultFont { x = 4, y = 4, w = 120, h = 20 } ("Score " ++ String.fromInt model.score)
         , Ui.text Resources.DefaultFont { x = 4, y = 24, w = 120, h = 20 } ("Best " ++ String.fromInt model.best)
         ]
            ++ List.concatMap drawTube model.tubes
            ++ (if model.alive then
                    []

                else
                    [ Ui.text Resources.DefaultFont { x = 24, y = 76, w = 100, h = 28 } "Press Up" ]
               )
        )


drawTube : Tube -> List Ui.RenderOp
drawTube tube =
    [ Ui.fillRect { x = tube.x, y = 0, w = 22, h = tube.gapY } Color.black
    , Ui.fillRect { x = tube.x, y = tube.gapY + 46, w = 22, h = 168 - tube.gapY - 46 } Color.black
    ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
