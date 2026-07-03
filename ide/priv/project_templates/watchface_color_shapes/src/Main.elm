module Main exposing (main)

{-|

Color and shape diagnostic watchface for emulator bring-up.

No companion, subscriptions, or time APIs — only static draw commands.

Expected on a colour Pebble (for example Gabbro 260×260):

- Top row: red, green, blue filled rectangles
- Centre: blue-moon wedge on the outer ring, black inner disk, chrome-yellow sun wedge
- Bottom row: orange, magenta, and white filled circles

If the top row is greyscale but the centre sun arc is missing, radial fills are broken.
If everything is black and white, colour mapping or VNC correction is broken.

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
    Ui.windowStack
        [ Ui.window 1
            [ Ui.canvasLayer 1 (sceneOps model)
            ]
        ]


sceneOps : Model -> List Ui.RenderOp
sceneOps model =
    let
        w =
            model.screenW

        h =
            model.screenH

        pad =
            4

        stripH =
            max 12 (h // 8)

        colW =
            w // 3

        lastColW =
            w - (colW * 2)

        cx =
            w // 2

        cy =
            h // 2

        radius =
            (min w h // 2) - pad

        innerRadius =
            radius - 14

        bottomY =
            h - stripH - pad

        circleY =
            bottomY + (stripH // 2)

        circleR =
            max 8 (stripH // 2 - 2)

        moonBounds =
            square cx cy radius

        sunBounds =
            square cx cy innerRadius

        third =
            w // 3
    in
    [ Ui.clear Color.oxfordBlue
    , Ui.fillRect { x = 0, y = pad, w = colW, h = stripH } Color.red
    , Ui.fillRect { x = colW, y = pad, w = colW, h = stripH } Color.green
    , Ui.fillRect { x = colW * 2, y = pad, w = lastColW, h = stripH } Color.blue
    , Ui.rect { x = 0, y = pad, w = colW, h = stripH } Color.white
    , Ui.rect { x = colW, y = pad, w = colW, h = stripH } Color.white
    , Ui.rect { x = colW * 2, y = pad, w = lastColW, h = stripH } Color.white
    , coloredRadial moonBounds Color.blueMoon angleSouth angleEast
    , Ui.fillCircle { x = cx, y = cy } innerRadius Color.black
    , coloredRadial sunBounds Color.chromeYellow angleTop angleSouth
    , Ui.fillCircle { x = third // 2, y = circleY } circleR Color.orange
    , Ui.fillCircle { x = cx, y = circleY } circleR Color.magenta
    , Ui.fillCircle { x = w - (third // 2), y = circleY } circleR Color.white
    , Ui.circle { x = cx, y = cy } innerRadius Color.lightGray
    ]


coloredRadial : Ui.Rect -> Color.Color -> Int -> Int -> Ui.RenderOp
coloredRadial bounds fill start end =
    Ui.group
        (Ui.context
            [ Ui.fillColor fill, Ui.strokeColor fill ]
            [ Ui.fillRadial bounds start end ]
        )


square : Int -> Int -> Int -> Ui.Rect
square centerX centerY r =
    { x = centerX - r, y = centerY - r, w = r * 2, h = r * 2 }


{-| Pebble angles: 0 = top (north), increase clockwise (65536 = full turn).
-}
angleTop : Int
angleTop =
    0


angleSouth : Int
angleSouth =
    32768


angleEast : Int
angleEast =
    49152


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
