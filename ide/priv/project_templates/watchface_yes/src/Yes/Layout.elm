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
    , topLeftIcon : { x : Int, y : Int }
    , topRightDate : Ui.Rect
    , bottomLeftWeather : Ui.Rect
    , bottomLeftWeatherVector : { x : Int, y : Int }
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
            screenW // 2 + pad

        bottomRightBottom =
            screenH - pad

        textW =
            screenW - bottomRightX - pad

        -- Match FONT_KEY_GOTHIC_18 box height so device glyphs are not clipped away.
        lineH =
            18

        -- Weather PDCs are 48x48; text must start to the right of that box or
        -- white glyphs sit on the white icon and disappear.
        weatherIconSize =
            48

        weatherIconX =
            0

        weatherTextX =
            weatherIconX + weatherIconSize + 2
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
    , topLeftTitle = { x = pad, y = pad, w = 40, h = 18 }
    , topLeftIcon = { x = pad, y = pad + 18 }
    , topRightDate = { x = screenW // 2, y = pad, w = screenW // 2 - pad, h = lineH }
    , bottomLeftWeather =
        { x = weatherTextX
        , y = bottomRightBottom - lineH
        , w = max 0 (screenW // 2 - weatherTextX - pad)
        , h = lineH
        }
    , bottomLeftWeatherVector = { x = weatherIconX, y = bottomRightBottom - weatherIconSize }
    , bottomRight =
        { x = bottomRightX
        , bottom = bottomRightBottom
        , textW = textW
        , lineH = lineH
        , vector = { x = screenW - pad - 36, y = bottomRightBottom - 40 }
        , singleLine =
            { x = bottomRightX
            , y = bottomRightBottom - lineH
            , w = textW
            , h = lineH
            }
        , countdownLabelH = 14
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
