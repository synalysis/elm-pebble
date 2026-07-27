module Yes.Layout exposing (BottomRightLayout, Layout, centerSquare, fromScreen, scalePx)

import Pebble.Ui as Ui


type alias Layout =
    { screenW : Int
    , screenH : Int
    , cx : Int
    , cy : Int
    , minDim : Int
    , outerRadius : Int
    , innerRadius : Int
    , moonY : Int
    , moonPhaseRadius : Int
    , timeTextBand : Ui.Rect
    , hubR : Int
    , moonRingR : Int
    , handLen : Int
    , pad : Int
    , topLeftTitle : Ui.Rect
    , topLeftLabel : Ui.Rect
    , topRightDate : Ui.Rect
    , bottomLeftWeather : Ui.Rect
    , bottomRight : BottomRightLayout
    }


type alias BottomRightLayout =
    { x : Int
    , bottom : Int
    , textW : Int
    , lineH : Int
    , vector : { x : Int, y : Int }
    , singleLine : Ui.Rect
    , countdownLabelH : Int
    , countdownTimeH : Int
    }


baseFaceRadius : Int
baseFaceRadius =
    72


{-| Scale a Basalt-baseline pixel value to the current face radius.
-}
scalePx : Int -> Int -> Int
scalePx basePx faceRadius =
    if faceRadius <= 0 then
        basePx

    else
        max 1 ((basePx * faceRadius + (baseFaceRadius // 2)) // baseFaceRadius)


fromScreen : Int -> Int -> Layout
fromScreen screenW screenH =
    let
        minDim =
            min screenW screenH

        cx =
            screenW // 2

        cy =
            screenH // 2

        outerRadius =
            minDim // 2 - 22

        innerRadius =
            outerRadius - 5

        moonY =
            cy + minDim // 5

        moonPhaseRadius =
            max 10 (outerRadius // 5)

        timeTextY =
            cy - (outerRadius // 2) - 14

        hubR =
            max 4 (outerRadius * 6 // 50)

        moonRingR =
            max 8 (outerRadius * 10 // 50)

        handLen =
            outerRadius - max 10 (outerRadius * 18 // 50)

        pad =
            max 4 (minDim // 36)

        bottomRightX =
            screenW - 64

        bottomRightBottom =
            screenH - pad

        textW =
            62

        lineH =
            14
    in
    { screenW = screenW
    , screenH = screenH
    , cx = cx
    , cy = cy
    , minDim = minDim
    , outerRadius = outerRadius
    , innerRadius = innerRadius
    , moonY = moonY
    , moonPhaseRadius = moonPhaseRadius
    , timeTextBand = { x = 0, y = timeTextY, w = screenW, h = 28 }
    , hubR = hubR
    , moonRingR = moonRingR
    , handLen = handLen
    , pad = pad
    , topLeftTitle = { x = pad, y = pad, w = 40, h = 16 }
    , topLeftLabel = { x = pad, y = pad + 16, w = 44, h = 12 }
    , topRightDate = { x = screenW - 52, y = pad, w = 48, h = lineH }
    , bottomLeftWeather = { x = pad, y = bottomRightBottom - lineH, w = screenW // 2 - pad, h = lineH }
    , bottomRight =
        { x = bottomRightX
        , bottom = bottomRightBottom
        , textW = textW
        , lineH = lineH
        , vector = { x = bottomRightX + 3, y = bottomRightBottom - 38 }
        , singleLine = { x = bottomRightX, y = bottomRightBottom - lineH, w = 60, h = lineH }
        , countdownLabelH = 12
        , countdownTimeH = lineH
        }
    }


centerSquare : Layout -> Int -> Ui.Rect
centerSquare layout radius =
    { x = layout.cx - radius
    , y = layout.cy - radius
    , w = radius * 2
    , h = radius * 2
    }
