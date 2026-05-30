module Pebble.Ui exposing
    ( AnimatedBitmap
    , AnimatedVector
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
    , TextAlignment(..)
    , TextOptions
    , TextOverflow(..)
    , StaticBitmap
    , StaticVector
    , UiNode
    , WindowNode
    , alignCenter
    , alignLeft
    , alignRight
    , antialiased
    , arc
    , canvasLayer
    , circle
    , clear
    , compositingMode
    , context
    , defaultTextOptions
    , drawBitmapInRect
    , drawRotatedBitmap
    , drawVectorAt
    , drawVectorSequenceAt
    , fillCircle
    , fillColor
    , fillOverflow
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
    , trailingEllipsis
    , window
    , windowStack
    , wordWrap
    )

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

@docs RenderOp, text, textInt, textLabel, clear, fillRect, pixel, line, rect, circle, fillCircle, drawBitmapInRect, drawRotatedBitmap, drawVectorAt, drawVectorSequenceAt, group, pathFilled, pathOutline, pathOutlineOpen, roundRect, arc, fillRadial


# Resources, labels and path/context helpers

@docs Label, Context, StaticBitmap, AnimatedBitmap, StaticVector, AnimatedVector, Font, Path, Point, Rect, Rotation, TextAlignment, TextOverflow, TextOptions, defaultTextOptions, alignLeft, alignCenter, alignRight, wordWrap, trailingEllipsis, fillOverflow, context, path, rotationFromPebbleAngle, rotationFromDegrees


# Drawing settings

@docs ContextSetting, strokeWidth, antialiased, strokeColor, fillColor, textColor, compositingMode

-}
import Pebble.Ui.Color as UiColor
import Pebble.Ui.Resources as UiResources


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
    | Text Font Int Int Int Int Int Int String
    | Clear Int
    | Pixel Int Int Int
    | Line Int Int Int Int Int
    | RectOp Int Int Int Int Int
    | FillRect Int Int Int Int Int
    | Circle Int Int Int Int
    | FillCircle Int Int Int Int
    | Group Context
    | BitmapInRect StaticBitmap Int Int Int Int
    | RotatedBitmap StaticBitmap Int Int Int Int Int
    | VectorAt StaticVector Int Int
    | VectorSequenceAt AnimatedVector Int Int
    | BitmapSequenceAt AnimatedBitmap Int Int
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


{-| Static bitmap resource handle from `Pebble.Ui.Resources`.
-}
type alias StaticBitmap =
    UiResources.StaticBitmap


{-| Animated bitmap (APNG) resource handle from `Pebble.Ui.Resources`.
-}
type alias AnimatedBitmap =
    UiResources.AnimatedBitmap


{-| Font resource handle from `Pebble.Ui.Resources`.
-}
type alias Font =
    UiResources.Font


{-| Static vector resource handle from `Pebble.Ui.Resources`.
-}
type alias StaticVector =
    UiResources.StaticVector


{-| Animated vector sequence resource handle from `Pebble.Ui.Resources`.
-}
type alias AnimatedVector =
    UiResources.AnimatedVector


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


{-| Horizontal alignment for text drawn inside a rectangle.
-}
type TextAlignment
    = AlignLeft
    | AlignCenter
    | AlignRight


{-| Overflow behavior for text that does not fit inside its rectangle.
-}
type TextOverflow
    = WordWrap
    | TrailingEllipsis
    | Fill


{-| Options passed to Pebble text layout.
-}
type alias TextOptions =
    { alignment : TextAlignment
    , overflow : TextOverflow
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
text : Font -> TextOptions -> Rect -> String -> RenderOp
text font options bounds value =
    Text font bounds.x bounds.y bounds.w bounds.h (textAlignmentToInt options.alignment) (textOverflowToInt options.overflow) value


{-| Default Pebble text options: centered, word-wrapped text.
-}
defaultTextOptions : TextOptions
defaultTextOptions =
    { alignment = AlignCenter
    , overflow = WordWrap
    }


{-| Set text alignment to left.
-}
alignLeft : TextOptions -> TextOptions
alignLeft options =
    { options | alignment = AlignLeft }


{-| Set text alignment to center.
-}
alignCenter : TextOptions -> TextOptions
alignCenter options =
    { options | alignment = AlignCenter }


{-| Set text alignment to right.
-}
alignRight : TextOptions -> TextOptions
alignRight options =
    { options | alignment = AlignRight }


{-| Use Pebble word wrapping for overflow.
-}
wordWrap : TextOptions -> TextOptions
wordWrap options =
    { options | overflow = WordWrap }


{-| Use Pebble trailing ellipsis for overflow.
-}
trailingEllipsis : TextOptions -> TextOptions
trailingEllipsis options =
    { options | overflow = TrailingEllipsis }


{-| Use Pebble fill overflow behavior.
-}
fillOverflow : TextOptions -> TextOptions
fillOverflow options =
    { options | overflow = Fill }


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
    RectOp bounds.x bounds.y bounds.w bounds.h (UiColor.toInt color)


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
drawBitmapInRect : StaticBitmap -> Rect -> RenderOp
drawBitmapInRect bitmap bounds =
    BitmapInRect bitmap bounds.x bounds.y bounds.w bounds.h


{-| Draw bitmap resource using width/height, angle and center point.
-}
drawRotatedBitmap : StaticBitmap -> Rect -> Rotation -> Point -> RenderOp
drawRotatedBitmap bitmap srcRect rotation center =
    RotatedBitmap bitmap srcRect.w srcRect.h (rotationToPebbleAngle rotation) center.x center.y


{-| Draw a static vector resource at the given origin.
-}
drawVectorAt : StaticVector -> Point -> RenderOp
drawVectorAt vector origin =
    VectorAt vector origin.x origin.y


{-| Draw an animated vector sequence at the given origin.
-}
drawVectorSequenceAt : AnimatedVector -> Point -> RenderOp
drawVectorSequenceAt vector origin =
    VectorSequenceAt vector origin.x origin.y


{-| Draw an animated bitmap (APNG) sequence at the given origin.
-}
drawBitmapSequenceAt : AnimatedBitmap -> Point -> RenderOp
drawBitmapSequenceAt animation origin =
    BitmapSequenceAt animation origin.x origin.y


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


textAlignmentToInt : TextAlignment -> Int
textAlignmentToInt alignment =
    case alignment of
        AlignLeft ->
            0

        AlignCenter ->
            1

        AlignRight ->
            2


textOverflowToInt : TextOverflow -> Int
textOverflowToInt overflow =
    case overflow of
        WordWrap ->
            0

        TrailingEllipsis ->
            1

        Fill ->
            2


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
