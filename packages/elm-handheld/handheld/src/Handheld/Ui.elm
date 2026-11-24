module Handheld.Ui exposing
    ( Point
    , Rect
    , circle
    , clear
    , fill
    , fillCircle
    , line
    , pixel
    , rect
    , text
    )

{-| Draw the panel.

Return commands from `view`. The runtime plays them in order, so later
commands paint over earlier ones. `Cmd.batch` groups a frame.

    import Handheld.Color as Color
    import Handheld.Ui as Ui

    view model =
        Cmd.batch
            [ Ui.clear Color.black
            , Ui.fill
                { x = 0
                , y = model.height // 2
                , width = model.width
                , height = 8
                }
                Color.white
            , Ui.text { x = 4, y = 4 } (String.fromInt model.score) Color.white
            ]

Coordinates start at the top left. Width and height come from
`context.screen` in `init`.

# Geometry
@docs Point, Rect

# Drawing
@docs clear, pixel, line, rect, fill, circle, fillCircle, text
-}

import Handheld.Color exposing (Color)
import Handheld.Raw as Raw


{-| A pixel position.
-}
type alias Point =
    { x : Int
    , y : Int
    }


{-| An axis-aligned rectangle.
-}
type alias Rect =
    { x : Int
    , y : Int
    , width : Int
    , height : Int
    }


{-| Fill the panel with one color.
-}
clear : Color -> Cmd msg
clear _ =
    Raw.none


{-| Draw one pixel.
-}
pixel : Point -> Color -> Cmd msg
pixel _ _ =
    Raw.none


{-| Draw a straight line from one point to another.
-}
line : Point -> Point -> Color -> Cmd msg
line _ _ _ =
    Raw.none


{-| Stroke a rectangle.
-}
rect : Rect -> Color -> Cmd msg
rect _ _ =
    Raw.none


{-| Fill a rectangle.
-}
fill : Rect -> Color -> Cmd msg
fill _ _ =
    Raw.none


{-| Stroke a circle. The radius is in pixels.
-}
circle : Point -> Int -> Color -> Cmd msg
circle _ _ _ =
    Raw.none


{-| Fill a circle. The radius is in pixels.
-}
fillCircle : Point -> Int -> Color -> Cmd msg
fillCircle _ _ _ =
    Raw.none


{-| Draw a string with its top left at a point.
-}
text : Point -> String -> Color -> Cmd msg
text _ _ _ =
    Raw.none
