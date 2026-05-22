module Pebble.Game.Collision exposing
    ( Circle
    , Rect
    , circleCircle
    , pointInRect
    , rectRect
    )

{-| Small collision helpers for simple 2D watch games.

# Shapes
@docs Rect, Circle

# Tests
@docs rectRect, pointInRect, circleCircle

-}

{-| Axis-aligned rectangle bounds.
-}
type alias Rect =
    { x : Int
    , y : Int
    , w : Int
    , h : Int
    }


{-| Circle bounds with integer center and radius.
-}
type alias Circle =
    { x : Int
    , y : Int
    , r : Int
    }


{-| Check whether two axis-aligned rectangles overlap.
-}
rectRect : Rect -> Rect -> Bool
rectRect a b =
    a.x
        < b.x
        + b.w
        && a.x
        + a.w
        > b.x
        && a.y
        < b.y
        + b.h
        && a.y
        + a.h
        > b.y


{-| Check whether a point is inside a rectangle.
-}
pointInRect : { x : Int, y : Int } -> Rect -> Bool
pointInRect point rect =
    point.x
        >= rect.x
        && point.x
        < rect.x
        + rect.w
        && point.y
        >= rect.y
        && point.y
        < rect.y
        + rect.h


{-| Check whether two circles overlap.
-}
circleCircle : Circle -> Circle -> Bool
circleCircle a b =
    let
        dx =
            a.x - b.x

        dy =
            a.y - b.y

        radius =
            a.r + b.r
    in
    dx * dx + dy * dy <= radius * radius
