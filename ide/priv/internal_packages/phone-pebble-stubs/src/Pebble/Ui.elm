module Pebble.Ui exposing
    ( Bitmap
    , Context
    , ContextSetting(..)
    , Font
    , Label(..)
    , LayerNode
    , Path
    , Point
    , Rect
    , RenderOp
    , Rotation
    , UiNode
    , WindowNode
    , antialiased
    , arc
    , canvasLayer
    , circle
    , clear
    , compositingMode
    , context
    , drawBitmapInRect
    , drawRotatedBitmap
    , fillCircle
    , fillColor
    , fillRadial
    , fillRect
    , group
    , line
    , path
    , pathFilled
    , pathOutline
    , pathOutlineOpen
    , pixel
    , rect
    , rotationFromDegrees
    , rotationFromPebbleAngle
    , roundRect
    , strokeColor
    , strokeWidth
    , text
    , textColor
    , textInt
    , textLabel
    , toUiNode
    , window
    , windowStack
    )

import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type UiNode
    = WindowStack (List WindowNode)
    | RootCanvas (List RenderOp)


type WindowNode
    = WindowNode Int (List LayerNode)


type LayerNode
    = CanvasLayer Int (List RenderOp)


type RenderOp
    = RenderOp


type Label
    = WaitingForCompanion


type alias Context =
    ( List ContextSetting, List RenderOp )


type alias Bitmap =
    Resources.Bitmap


type alias Font =
    Resources.Font


type alias Path =
    ( List ( Int, Int ), ( Int, Int ), Int )


type alias Point =
    { x : Int
    , y : Int
    }


type alias Rect =
    { x : Int
    , y : Int
    , w : Int
    , h : Int
    }


type Rotation
    = Rotation Int


type ContextSetting
    = StrokeWidth Int
    | Antialiased Int
    | StrokeColor Int
    | FillColor Int
    | TextColor Int
    | CompositingMode Int


windowStack : List WindowNode -> UiNode
windowStack =
    WindowStack


window : Int -> List LayerNode -> WindowNode
window =
    WindowNode


canvasLayer : Int -> List RenderOp -> LayerNode
canvasLayer =
    CanvasLayer


toUiNode : List RenderOp -> UiNode
toUiNode =
    RootCanvas


textInt : Font -> Point -> Int -> RenderOp
textInt _ _ _ =
    RenderOp


textLabel : Font -> Point -> Label -> RenderOp
textLabel _ _ _ =
    RenderOp


text : Font -> Rect -> String -> RenderOp
text _ _ _ =
    RenderOp


clear : Color.Color -> RenderOp
clear _ =
    RenderOp


fillRect : Rect -> Color.Color -> RenderOp
fillRect _ _ =
    RenderOp


pixel : Point -> Color.Color -> RenderOp
pixel _ _ =
    RenderOp


line : Point -> Point -> Color.Color -> RenderOp
line _ _ _ =
    RenderOp


rect : Rect -> Color.Color -> RenderOp
rect _ _ =
    RenderOp


circle : Point -> Int -> Color.Color -> RenderOp
circle _ _ _ =
    RenderOp


fillCircle : Point -> Int -> Color.Color -> RenderOp
fillCircle _ _ _ =
    RenderOp


context : List ContextSetting -> List RenderOp -> Context
context settings ops =
    ( settings, ops )


drawBitmapInRect : Bitmap -> Rect -> RenderOp
drawBitmapInRect _ _ =
    RenderOp


drawRotatedBitmap : Bitmap -> Rect -> Rotation -> Point -> RenderOp
drawRotatedBitmap _ _ _ _ =
    RenderOp


group : Context -> RenderOp
group _ =
    RenderOp


path : List Point -> Point -> Rotation -> Path
path points origin (Rotation rotation) =
    ( List.map (\point -> ( point.x, point.y )) points, ( origin.x, origin.y ), rotation )


rotationFromPebbleAngle : Int -> Rotation
rotationFromPebbleAngle =
    Rotation


rotationFromDegrees : Float -> Rotation
rotationFromDegrees degrees =
    Rotation (round (degrees * 65536 / 360))


pathFilled : Path -> RenderOp
pathFilled _ =
    RenderOp


pathOutline : Path -> RenderOp
pathOutline _ =
    RenderOp


pathOutlineOpen : Path -> RenderOp
pathOutlineOpen _ =
    RenderOp


strokeWidth : Int -> ContextSetting
strokeWidth =
    StrokeWidth


antialiased : Int -> ContextSetting
antialiased =
    Antialiased


strokeColor : Color.Color -> ContextSetting
strokeColor color =
    StrokeColor (Color.toInt color)


fillColor : Color.Color -> ContextSetting
fillColor color =
    FillColor (Color.toInt color)


textColor : Color.Color -> ContextSetting
textColor color =
    TextColor (Color.toInt color)


roundRect : Rect -> Int -> Color.Color -> RenderOp
roundRect _ _ _ =
    RenderOp


arc : Rect -> Int -> Int -> RenderOp
arc _ _ _ =
    RenderOp


fillRadial : Rect -> Int -> Int -> RenderOp
fillRadial _ _ _ =
    RenderOp


compositingMode : Int -> ContextSetting
compositingMode =
    CompositingMode
