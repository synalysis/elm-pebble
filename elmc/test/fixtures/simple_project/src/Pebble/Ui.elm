module Pebble.Ui exposing
    ( Context
    , Bitmap
    , Font
    , ContextSetting(..)
    , Label(..)
    , LayerNode
    , Path
    , Point
    , Rect
    , Rotation
    , RenderOp
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
    , textColor
    , textInt
    , textLabel
    , window
    , windowStack
    )

import Pebble.Ui.Color as UiColor
import Pebble.Ui.Resources as UiResources



type UiNode
    = WindowStack (List WindowNode)


type WindowNode
    = WindowNode Int (List LayerNode)


type LayerNode
    = CanvasLayer Int (List RenderOp)


type RenderOp
    = TextInt Font Int Int Int
    | TextLabel Font Int Int Label
    | Clear Int
    | Pixel Int Int Int
    | Line Int Int Int Int Int
    | DrawRect Int Int Int Int Int
    | FillRect Int Int Int Int Int
    | Circle Int Int Int Int
    | FillCircle Int Int Int Int
    | Group Context
    | BitmapInRect Bitmap Int Int Int Int
    | RotatedBitmap Bitmap Int Int Int Int Int
    | PathFilled Path
    | PathOutline Path
    | PathOutlineOpen Path
    | RoundRect Int Int Int Int Int Int
    | Arc Int Int Int Int Int Int
    | FillRadial Int Int Int Int Int Int


type Label
    = WaitingForCompanion


type alias Context =
    ( List ContextSetting, List RenderOp )

type alias Bitmap =
    UiResources.Bitmap

type alias Font =
    UiResources.Font


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
windowStack windows =
    WindowStack windows


window : Int -> List LayerNode -> WindowNode
window id layers =
    WindowNode id layers


canvasLayer : Int -> List RenderOp -> LayerNode
canvasLayer id ops =
    CanvasLayer id ops


textInt : Font -> Point -> Int -> RenderOp
textInt font pos value =
    TextInt font pos.x pos.y value


textLabel : Font -> Point -> Label -> RenderOp
textLabel font pos label =
    TextLabel font pos.x pos.y label


clear : UiColor.Color -> RenderOp
clear color =
    Clear (UiColor.toInt color)


fillRect : Rect -> UiColor.Color -> RenderOp
fillRect bounds color =
    FillRect bounds.x bounds.y bounds.w bounds.h (UiColor.toInt color)


pixel : Point -> UiColor.Color -> RenderOp
pixel pos color =
    Pixel pos.x pos.y (UiColor.toInt color)


line : Point -> Point -> UiColor.Color -> RenderOp
line startPos endPos color =
    Line startPos.x startPos.y endPos.x endPos.y (UiColor.toInt color)


rect : Rect -> UiColor.Color -> RenderOp
rect bounds color =
    DrawRect bounds.x bounds.y bounds.w bounds.h (UiColor.toInt color)


circle : Point -> Int -> UiColor.Color -> RenderOp
circle center radius color =
    Circle center.x center.y radius (UiColor.toInt color)


fillCircle : Point -> Int -> UiColor.Color -> RenderOp
fillCircle center radius color =
    FillCircle center.x center.y radius (UiColor.toInt color)


context : List ContextSetting -> List RenderOp -> Context
context settings commands =
    ( settings, commands )


drawBitmapInRect : Bitmap -> Rect -> RenderOp
drawBitmapInRect bitmapId bounds =
    BitmapInRect bitmapId bounds.x bounds.y bounds.w bounds.h


drawRotatedBitmap : Bitmap -> Rect -> Rotation -> Point -> RenderOp
drawRotatedBitmap bitmapId srcRect rotation center =
    RotatedBitmap bitmapId srcRect.w srcRect.h (rotationToPebbleAngle rotation) center.x center.y


group : Context -> RenderOp
group ctx =
    Group ctx


path : List Point -> Point -> Rotation -> Path
path points offset rotation =
    ( List.map (\p -> ( p.x, p.y )) points
    , ( offset.x, offset.y )
    , rotationToPebbleAngle rotation
    )


rotationFromPebbleAngle : Int -> Rotation
rotationFromPebbleAngle angle =
    Rotation angle


rotationFromDegrees : Float -> Rotation
rotationFromDegrees degrees =
    Rotation (round ((degrees * 65536) / 360))


rotationToPebbleAngle : Rotation -> Int
rotationToPebbleAngle (Rotation angle) =
    angle


pathFilled : Path -> RenderOp
pathFilled value =
    PathFilled value


pathOutline : Path -> RenderOp
pathOutline value =
    PathOutline value


pathOutlineOpen : Path -> RenderOp
pathOutlineOpen value =
    PathOutlineOpen value


strokeWidth : Int -> ContextSetting
strokeWidth width =
    StrokeWidth width


antialiased : Int -> ContextSetting
antialiased enabled =
    Antialiased enabled


strokeColor : UiColor.Color -> ContextSetting
strokeColor color =
    StrokeColor (UiColor.toInt color)


fillColor : UiColor.Color -> ContextSetting
fillColor color =
    FillColor (UiColor.toInt color)


textColor : UiColor.Color -> ContextSetting
textColor color =
    TextColor (UiColor.toInt color)


roundRect : Rect -> Int -> UiColor.Color -> RenderOp
roundRect bounds radius color =
    RoundRect bounds.x bounds.y bounds.w bounds.h radius (UiColor.toInt color)


arc : Rect -> Int -> Int -> RenderOp
arc bounds angleStart angleEnd =
    Arc bounds.x bounds.y bounds.w bounds.h angleStart angleEnd


fillRadial : Rect -> Int -> Int -> RenderOp
fillRadial bounds angleStart angleEnd =
    FillRadial bounds.x bounds.y bounds.w bounds.h angleStart angleEnd


compositingMode : Int -> ContextSetting
compositingMode mode =
    CompositingMode mode
