module Pebble.Touch exposing
    ( Axis(..)
    , Direction(..)
    , PanEvent
    , Phase(..)
    , Point
    , SwipeEvent
    , enableNavigation
    , onPan
    , onSwipe
    , onTap
    , supported
    )

{-| Touch gestures for Pebble watch **apps** (not watchfaces).

The Pebble SDK currently restricts touch to watchapps. Subscribe from
`Platform.application`, not `Platform.watchface`. On watches without a
touchscreen, or when the user disables Touch in Settings, `supported`
returns `False` and gesture subscriptions do not fire.

    import Pebble.Touch as Touch

    type Msg
        = TouchSupported Bool
        | Tapped Touch.Point
        | Panned Touch.PanEvent
        | Swiped Touch.SwipeEvent

    init _ =
        ( model
        , Cmd.batch
            [ Touch.supported TouchSupported
            , Touch.enableNavigation
            ]
        )

    subscriptions _ =
        Sub.batch
            [ Touch.onTap Tapped
            , Touch.onPan Touch.Vertical Panned
            , Touch.onSwipe [ Touch.Left, Touch.Right ] Swiped
            ]

`enableNavigation` lets the system map taps and swipes to button events so
existing `Pebble.Button` subscriptions keep working. Do **not** enable
navigation on a window that also uses `onTap` / `onPan` / `onSwipe` — the
system would consume those touches.

For a runnable example, use the **watch-demo-touch** project template in the IDE.

Gesture APIs require SDK/firmware 4.33+. On older firmware, `supported`
is `False` and recognizers are not attached.

# Types
@docs Point, Phase, Axis, Direction, PanEvent, SwipeEvent

# Commands
@docs supported, enableNavigation

# Subscriptions
@docs onTap, onPan, onSwipe

-}

import Elm.Kernel.PebbleWatch


{-| Screen-relative pixel coordinate.
-}
type alias Point =
    { x : Int
    , y : Int
    }


{-| Recognizer progress.
-}
type Phase
    = Started
    | Updated
    | Completed
    | Cancelled


{-| Axis lock for `onPan`.
-}
type Axis
    = Horizontal
    | Vertical


{-| Swipe direction reported by `onSwipe`.
-}
type Direction
    = Up
    | Down
    | Left
    | Right


{-| A pan (single-axis drag) update.
-}
type alias PanEvent =
    { phase : Phase
    , totalX : Int
    , totalY : Int
    , sinceStartX : Int
    , sinceStartY : Int
    , velocityX : Int
    , velocityY : Int
    }


{-| A completed swipe.
-}
type alias SwipeEvent =
    { direction : Direction
    , velocityX : Int
    , velocityY : Int
    }


{-| Request whether touch input is available right now.

Returns `False` when the hardware has no touchscreen or the user disabled
Touch in Settings.
-}
supported : (Bool -> msg) -> Cmd msg
supported =
    Elm.Kernel.PebbleWatch.touchSupported


{-| Opt in to system touch navigation (taps/swipes become button events).
-}
enableNavigation : Cmd msg
enableNavigation =
    Elm.Kernel.PebbleWatch.touchEnableNavigation


{-| Receive recognized taps with the tap point.
-}
onTap : (Point -> msg) -> Sub msg
onTap =
    Elm.Kernel.PebbleWatch.onTouchTap


{-| Receive pan updates locked to `axis`.
-}
onPan : Axis -> (PanEvent -> msg) -> Sub msg
onPan axis toMsg =
    case axis of
        Horizontal ->
            Elm.Kernel.PebbleWatch.onTouchPanHorizontal toMsg

        Vertical ->
            Elm.Kernel.PebbleWatch.onTouchPanVertical toMsg


{-| Receive completed swipes.

The direction list is a filter hint for the host. The event still reports
the recognized `Direction`.
-}
onSwipe : List Direction -> (SwipeEvent -> msg) -> Sub msg
onSwipe directions toMsg =
    Elm.Kernel.PebbleWatch.onTouchSwipe (directionMask directions) toMsg


directionMask directions =
    List.foldl
        (\direction acc -> acc + directionBit direction)
        0
        directions


directionBit direction =
    case direction of
        Up ->
            1

        Down ->
            2

        Left ->
            4

        Right ->
            8
