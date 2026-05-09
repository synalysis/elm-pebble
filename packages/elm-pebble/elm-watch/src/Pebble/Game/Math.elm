module Pebble.Game.Math exposing
    ( Vec2
    , add
    , clamp
    , distanceSquared
    , lengthSquared
    , scale
    , sub
    , vec2
    )

{-| Small math helpers for game and animation code.

# Vectors
@docs Vec2, vec2, add, sub, scale, lengthSquared, distanceSquared

# Scalars
@docs clamp

-}

{-| Two-dimensional floating-point vector.
-}
type alias Vec2 =
    { x : Float
    , y : Float
    }


{-| Construct a vector from x/y components.
-}
vec2 : Float -> Float -> Vec2
vec2 x y =
    { x = x, y = y }


{-| Add two vectors.
-}
add : Vec2 -> Vec2 -> Vec2
add a b =
    { x = a.x + b.x, y = a.y + b.y }


{-| Subtract the second vector from the first.
-}
sub : Vec2 -> Vec2 -> Vec2
sub a b =
    { x = a.x - b.x, y = a.y - b.y }


{-| Scale a vector by a scalar factor.
-}
scale : Float -> Vec2 -> Vec2
scale factor v =
    { x = v.x * factor, y = v.y * factor }


{-| Squared vector length.

Use this when comparing distances without needing the square root.
-}
lengthSquared : Vec2 -> Float
lengthSquared v =
    v.x * v.x + v.y * v.y


{-| Squared distance between two vectors.
-}
distanceSquared : Vec2 -> Vec2 -> Float
distanceSquared a b =
    lengthSquared (sub a b)


{-| Clamp a value between lower and upper bounds.
-}
clamp : comparable -> comparable -> comparable -> comparable
clamp lo hi value =
    if value < lo then
        lo

    else if value > hi then
        hi

    else
        value
