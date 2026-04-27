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

import Pebble.Ui.Color as UiColor
import Pebble.Ui.Resources as UiResources


{-| Retained virtual UI model for Pebble rendering.

`Pebble.Ui` provides a declarative scene graph for watch windows, layers,
and drawing operations. Build values here and emit them through your app's
render bridge to keep view logic in pure Elm.

    mainWindow : WindowNode
    mainWindow =
        window 1
            [ canvasLayer 2
                [ fillRect
                    { x = 0, y = 0, w = 144, h = 168 }
                    UiColor.black
                ]
            ]


# Core nodes

@docs UiNode, WindowNode, LayerNode, toUiNode, windowStack, window, canvasLayer


# Drawing operations

@docs RenderOp, text, textInt, textLabel, clear, fillRect, pixel, line, rect, circle, fillCircle, drawBitmapInRect, drawRotatedBitmap, group, pathFilled, pathOutline, pathOutlineOpen, roundRect, arc, fillRadial


# Resources, labels and path/context helpers

@docs Label, Context, Bitmap, Font, Path, Point, Rect, Rotation, context, path, rotationFromPebbleAngle, rotationFromDegrees


# Drawing settings

@docs ContextSetting, strokeWidth, antialiased, strokeColor, fillColor, textColor, compositingMode

-}


{-| Root virtual UI node.
-}
type UiNode
    = WindowStack (List WindowNode)


{-| A virtual window identified by a stable id.
-}
type WindowNode
    = WindowNode Int (List LayerNode)


{-| A virtual layer identified by a stable id.
-}
type LayerNode
    = CanvasLayer Int (List RenderOp)


{-| Drawing operations for a canvas layer.
-}
type RenderOp
    = TextInt Font Int Int Int
    | TextLabel Font Int Int Label
    | Text Font Int Int Int Int String
    | Clear Int
    | Pixel Int Int Int
    | Line Int Int Int Int Int
    | Rect Int Int Int Int Int
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


{-| Localized labels produced in Elm and rendered on watch.
-}
type Label
    = WaitingForCompanion


{-| Nested drawing context containing style settings and commands.
-}
type alias Context =
    ( List ContextSetting, List RenderOp )


{-| Bitmap resource handle from `Pebble.Ui.Resources`.
-}
type alias Bitmap =
    UiResources.Bitmap


{-| Font resource handle from `Pebble.Ui.Resources`.
-}
type alias Font =
    UiResources.Font


{-| Path geometry for path draw operations.
-}
type alias Path =
    ( List ( Int, Int ), ( Int, Int ), Int )


{-| 2D point for draw positions.
-}
type alias Point =
    { x : Int
    , y : Int
    }


{-| Rectangle bounds for draw operations.
-}
type alias Rect =
    { x : Int
    , y : Int
    , w : Int
    , h : Int
    }


{-| Rotation value for Pebble graphics APIs.

Use `rotationFromPebbleAngle` when you already have Pebble angle units
(`TRIG_MAX_ANGLE == 65536`) or `rotationFromDegrees` for degree inputs.

-}
type Rotation
    = Rotation Int


{-| Drawing style settings used by `context`.
-}
type ContextSetting
    = StrokeWidth Int
    | Antialiased Int
    | StrokeColor Int
    | FillColor Int
    | TextColor Int
    | CompositingMode Int


{-| Build a window stack node.
-}
windowStack : List WindowNode -> UiNode
windowStack windows =
    WindowStack windows


{-| Build a window node with a stable id and layers.
-}
window : Int -> List LayerNode -> WindowNode
window id layers =
    WindowNode id layers


{-| Build a canvas layer node with a stable id and draw operations.
-}
canvasLayer : Int -> List RenderOp -> LayerNode
canvasLayer id ops =
    CanvasLayer id ops


{-| Build a complete single-window UI from drawing operations.

This is a convenience for watchfaces and apps whose view is just one canvas.
It is equivalent to:

    windowStack
        [ window 1
            [ canvasLayer 1 ops ]
        ]

-}
toUiNode : List RenderOp -> UiNode
toUiNode ops =
    windowStack
        [ window 1
            [ canvasLayer 1 ops ]
        ]


{-| Draw an integer at the given position using a custom resource font.
-}
textInt : Font -> Point -> Int -> RenderOp
textInt font pos value =
    TextInt font pos.x pos.y value


{-| Draw a predefined label at the given position using a custom resource font.
-}
textLabel : Font -> Point -> Label -> RenderOp
textLabel font pos label =
    TextLabel font pos.x pos.y label


{-| Draw a string in the given rectangle using a resource font.
-}
text : Font -> Rect -> String -> RenderOp
text font bounds value =
    Text font bounds.x bounds.y bounds.w bounds.h value


{-| Clear the canvas to a color.
-}
clear : UiColor.Color -> RenderOp
clear color =
    Clear (UiColor.toInt color)


{-| Fill a rectangle with a color.
-}
fillRect : Rect -> UiColor.Color -> RenderOp
fillRect bounds color =
    FillRect bounds.x bounds.y bounds.w bounds.h (UiColor.toInt color)


{-| Draw a single pixel with a color.
-}
pixel : Point -> UiColor.Color -> RenderOp
pixel pos color =
    Pixel pos.x pos.y (UiColor.toInt color)


{-| Draw a line with a color.
-}
line : Point -> Point -> UiColor.Color -> RenderOp
line startPos endPos color =
    Line startPos.x startPos.y endPos.x endPos.y (UiColor.toInt color)


{-| Draw a rectangle outline with a color.
-}
rect : Rect -> UiColor.Color -> RenderOp
rect bounds color =
    Rect bounds.x bounds.y bounds.w bounds.h (UiColor.toInt color)


{-| Draw a circle outline with a color.
-}
circle : Point -> Int -> UiColor.Color -> RenderOp
circle center radius color =
    Circle center.x center.y radius (UiColor.toInt color)


{-| Draw a filled circle with a color.
-}
fillCircle : Point -> Int -> UiColor.Color -> RenderOp
fillCircle center radius color =
    FillCircle center.x center.y radius (UiColor.toInt color)


{-| Build a drawing context from settings and nested operations.
-}
context : List ContextSetting -> List RenderOp -> Context
context settings commands =
    ( settings, commands )


{-| Draw bitmap resource in the provided rectangle.
-}
drawBitmapInRect : Bitmap -> Rect -> RenderOp
drawBitmapInRect bitmap bounds =
    BitmapInRect bitmap bounds.x bounds.y bounds.w bounds.h


{-| Draw bitmap resource using width/height, angle and center point.
-}
drawRotatedBitmap : Bitmap -> Rect -> Rotation -> Point -> RenderOp
drawRotatedBitmap bitmap srcRect rotation center =
    RotatedBitmap bitmap srcRect.w srcRect.h (rotationToPebbleAngle rotation) center.x center.y


{-| Group operations under a temporary style context.
-}
group : Context -> RenderOp
group ctx =
    Group ctx


{-| Build path data from points, offset and rotation.
-}
path : List Point -> Point -> Rotation -> Path
path points offset rotation =
    ( List.map (\p -> ( p.x, p.y )) points
    , ( offset.x, offset.y )
    , rotationToPebbleAngle rotation
    )


{-| Create a rotation from raw Pebble angle units (`0..65535`).
-}
rotationFromPebbleAngle : Int -> Rotation
rotationFromPebbleAngle angle =
    Rotation angle


{-| Create a rotation from degrees.
-}
rotationFromDegrees : Float -> Rotation
rotationFromDegrees degrees =
    Rotation (round ((degrees * 65536) / 360))


rotationToPebbleAngle : Rotation -> Int
rotationToPebbleAngle (Rotation angle) =
    angle


{-| Draw a filled path.
-}
pathFilled : Path -> RenderOp
pathFilled value =
    PathFilled value


{-| Draw a closed path outline.
-}
pathOutline : Path -> RenderOp
pathOutline value =
    PathOutline value


{-| Draw an open path outline.
-}
pathOutlineOpen : Path -> RenderOp
pathOutlineOpen value =
    PathOutlineOpen value


{-| Set stroke width for a context.
-}
strokeWidth : Int -> ContextSetting
strokeWidth width =
    StrokeWidth width


{-| Enable or disable antialiasing (`0` or `1`).
-}
antialiased : Int -> ContextSetting
antialiased enabled =
    Antialiased enabled


{-| Set stroke color for a context.
-}
strokeColor : UiColor.Color -> ContextSetting
strokeColor color =
    StrokeColor (UiColor.toInt color)


{-| Set fill color for a context.
-}
fillColor : UiColor.Color -> ContextSetting
fillColor color =
    FillColor (UiColor.toInt color)


{-| Set text color for a context.
-}
textColor : UiColor.Color -> ContextSetting
textColor color =
    TextColor (UiColor.toInt color)


{-| Draw a rounded rectangle outline.
-}
roundRect : Rect -> Int -> UiColor.Color -> RenderOp
roundRect bounds radius color =
    RoundRect bounds.x bounds.y bounds.w bounds.h radius (UiColor.toInt color)


{-| Draw an arc inside rectangle bounds in Pebble angle units.
-}
arc : Rect -> Int -> Int -> RenderOp
arc bounds angleStart angleEnd =
    Arc bounds.x bounds.y bounds.w bounds.h angleStart angleEnd


{-| Draw a filled radial slice inside rectangle bounds.
-}
fillRadial : Rect -> Int -> Int -> RenderOp
fillRadial bounds angleStart angleEnd =
    FillRadial bounds.x bounds.y bounds.w bounds.h angleStart angleEnd


{-| Set graphics compositing mode (`0..4` Pebble `GCompOp`).
-}
compositingMode : Int -> ContextSetting
compositingMode mode =
    CompositingMode mode
