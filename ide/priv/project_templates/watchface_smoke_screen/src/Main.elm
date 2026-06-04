module Main exposing (main)

{-|

Smoke-screen watchface for emulator and device bring-up.

Expected live screenshot (any round or rect Pebble):

      +-------+-------+
      | BLACK | WHITE |
      +-------+-------+
      | WHITE | BLACK |
      +-------+-------+

Four equal quadrants in a checkerboard. No time APIs, fonts, bitmaps, or subscriptions.

-}

import Json.Decode as Decode
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color


type alias Model =
    { screenW : Int
    , screenH : Int
    }


type Msg
    = NoOp


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { screenW = context.screen.width
      , screenH = context.screen.height
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> Ui.UiNode
view model =
    let
        halfW =
            model.screenW // 2

        halfH =
            model.screenH // 2

        rightW =
            model.screenW - halfW

        bottomH =
            model.screenH - halfH
    in
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1
                [ Ui.clear Color.white
                , Ui.fillRect { x = 0, y = 0, w = halfW, h = halfH } Color.black
                , Ui.fillRect { x = halfW, y = 0, w = rightW, h = halfH } Color.white
                , Ui.fillRect { x = 0, y = halfH, w = halfW, h = bottomH } Color.white
                , Ui.fillRect { x = halfW, y = halfH, w = rightW, h = bottomH } Color.black
                ]
            ]
        ]


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
