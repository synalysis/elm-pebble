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


type alias Model =
    { x : Int
    , y : Int
    , vy : Int
    , best : Int
    }


type Msg
    = FrameTick Frame.Frame
    | UpPressed
    | UpReleased
    | StorageStringLoaded String


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { x = 18, y = 60, vy = 0, best = 0 }
    , Storage.readString 100 StorageStringLoaded
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FrameTick _ ->
            let
                nextY =
                    min 140 (model.y + model.vy)

                hit =
                    Collision.rectRect
                        { x = model.x, y = nextY, w = 14, h = 14 }
                        { x = 104, y = 112, w = 18, h = 36 }
            in
            ( { model | y = nextY, vy = min 8 (model.vy + 1), best = max model.best (140 - nextY) }
            , if hit then
                Vibes.shortPulse

              else
                Cmd.none
            )

        UpPressed ->
            ( { model | vy = -7 }, Cmd.none )

        UpReleased ->
            ( model, Storage.writeString 100 (String.fromInt model.best) )

        StorageStringLoaded value ->
            ( { model | best = Maybe.withDefault 0 (String.toInt value) }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Frame.every 33 FrameTick
        , Button.onPress Button.Up UpPressed
        , Button.onRelease Button.Up UpReleased
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.drawBitmapInRect Resources.NoBitmap { x = 0, y = 0, w = 1, h = 1 }
        , Ui.fillRect { x = model.x, y = model.y, w = 14, h = 14 } Color.black
        , Ui.rect { x = 104, y = 112, w = 18, h = 36 } Color.black
        , Ui.text Resources.DefaultFont { x = 4, y = 4, w = 120, h = 24 } ("Best " ++ String.fromInt model.best)
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
