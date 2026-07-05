module Yes.Render exposing (CornerSlots, FaceDisplay, SunWindow, face)

import Companion.Types exposing (Altitude(..), SunMode(..))
import List
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources
import Yes.Layout exposing (Layout)


type alias SunWindow =
    { sunriseMin : Int
    , sunsetMin : Int
    , mode : SunMode
    }


type alias FaceDisplay =
    { showCorners : Bool
    , homeMinute : Int
    , timeText : String
    , sun : Maybe SunWindow
    , moonPhaseE6 : Maybe Int
    , corners : CornerSlots
    }


type alias CornerSlots =
    { topLeft : { value : String, caption : String }
    , date : Maybe String
    , weather : Maybe String
    , bottomRight : BottomRightSlot
    }


type BottomRightSlot
    = AltitudeSlot String
    | SimpleLine String
    | CountdownSlot String String


face : Layout -> FaceDisplay -> List Ui.RenderOp
face layout display =
    [ Ui.clear Color.black ]
        ++ drawDial layout display
        ++ (if display.showCorners then
                drawCorners layout display.corners

            else
                []
           )


drawDial : Layout -> FaceDisplay -> List Ui.RenderOp
drawDial layout display =
    let
        sunWindow =
            Maybe.withDefault defaultSunWindow display.sun

        hasSunData =
            display.sun /= Nothing

        sunriseAngle =
            angleFromMinute sunWindow.sunriseMin

        sunsetAngle =
            angleFromMinute sunWindow.sunsetMin

        moonBounds =
            Yes.Layout.centerSquare layout layout.outerRadius

        sunBounds =
            Yes.Layout.centerSquare layout layout.innerRadius

        center =
            { x = layout.cx, y = layout.cy }
    in
    [ Ui.fillCircle center layout.outerRadius Color.oxfordBlue ]
        ++ (if hasSunData then
                coloredRadialWedge moonBounds Color.blueMoon sunriseAngle sunsetAngle

            else
                []
           )
        ++ [ Ui.fillCircle center layout.innerRadius Color.black ]
        ++ drawSunWindow center layout.innerRadius sunBounds sunriseAngle sunsetAngle sunWindow
        ++ [ Ui.circle center layout.outerRadius Color.white
           , Ui.circle center layout.innerRadius Color.darkGray
           ]
        ++ drawOuterScale layout
        ++ (case display.moonPhaseE6 of
                Just _ ->
                    drawMoonPhase layout

                Nothing ->
                    []
           )
        ++ draw24HourHand layout display.homeMinute
        ++ [ textAt Color.white layout.timeTextBand display.timeText ]


draw24HourHand : Layout -> Int -> List Ui.RenderOp
draw24HourHand layout nowMin =
    let
        handAngle =
            angleFromMinute nowMin

        tip =
            pointAt layout.cx layout.cy layout.handLen handAngle

        moonCenter =
            { x = layout.cx, y = layout.moonY }
    in
    [ Ui.fillCircle moonCenter layout.moonRingR Color.black
    , Ui.circle moonCenter layout.moonRingR Color.white
    , Ui.line { x = layout.cx, y = layout.cy } tip Color.white
    , Ui.fillCircle { x = layout.cx, y = layout.cy } layout.hubR Color.black
    , Ui.circle { x = layout.cx, y = layout.cy } layout.hubR Color.white
    ]


type alias TickSpec =
    { minute : Int
    , outerExtra : Int
    , label : Maybe String
    }


drawOuterScale : Layout -> List Ui.RenderOp
drawOuterScale layout =
    let
        oddTicks =
            List.map
                (\hour -> { minute = hour * 60, outerExtra = 10, label = Nothing })
                (List.range 1 23 |> List.filter (\h -> modBy 2 h == 1))

        evenTicks =
            List.map
                (\hour -> { minute = hour * 120, outerExtra = 6, label = Just (String.fromInt (hour * 2)) })
                (List.range 0 11)
    in
    List.concatMap (drawScaleTick layout) (oddTicks ++ evenTicks)


drawScaleTick : Layout -> TickSpec -> List Ui.RenderOp
drawScaleTick layout spec =
    let
        tickAngle =
            angleFromMinute spec.minute

        inner =
            pointAt layout.cx layout.cy layout.outerRadius tickAngle

        outer =
            pointAt layout.cx layout.cy (layout.outerRadius + spec.outerExtra) tickAngle
    in
    case spec.label of
        Nothing ->
            [ Ui.line outer inner Color.white ]

        Just value ->
            let
                labelPoint =
                    pointAt layout.cx layout.cy (layout.outerRadius + 14) tickAngle

                labelBox =
                    { x = labelPoint.x - 9, y = labelPoint.y - 14, w = 18, h = 12 }
            in
            [ Ui.line outer inner Color.white
            , textAt Color.white labelBox value
            ]


coloredRadial : Ui.Rect -> Color.Color -> Int -> Int -> List Ui.RenderOp
coloredRadial bounds fill start end =
    [ Ui.group
        (Ui.context
            [ Ui.fillColor fill, Ui.strokeColor fill ]
            [ Ui.fillRadial bounds start end ]
        )
    ]


coloredRadialWedge : Ui.Rect -> Color.Color -> Int -> Int -> List Ui.RenderOp
coloredRadialWedge bounds color startAngle endAngle =
    if endAngle < startAngle then
        coloredRadial bounds color startAngle 65536
            ++ coloredRadial bounds color 0 endAngle

    else
        coloredRadial bounds color startAngle endAngle


drawSunWindow : Ui.Point -> Int -> Ui.Rect -> Int -> Int -> SunWindow -> List Ui.RenderOp
drawSunWindow center radius bounds sunriseAngle sunsetAngle sunWindow =
    case sunWindow.mode of
        PolarNight ->
            []

        PolarDay ->
            [ Ui.fillCircle center radius Color.chromeYellow ]

        SunCycle ->
            coloredRadialWedge bounds Color.chromeYellow sunriseAngle sunsetAngle


drawMoonPhase : Layout -> List Ui.RenderOp
drawMoonPhase layout =
    let
        center =
            { x = layout.cx, y = layout.moonY }
    in
    [ Ui.fillCircle center layout.moonPhaseRadius Color.lightGray
    , Ui.circle center layout.moonPhaseRadius Color.white
    ]


drawCorners : Layout -> CornerSlots -> List Ui.RenderOp
drawCorners layout slots =
    drawTopLeft layout slots.topLeft
        ++ drawDate layout slots.date
        ++ drawWeatherCorner layout slots.weather
        ++ drawBottomRight layout slots.bottomRight


drawTopLeft : Layout -> { value : String, caption : String } -> List Ui.RenderOp
drawTopLeft layout slot =
    [ textAt Color.white layout.topLeftTitle slot.value
    , textAt Color.darkGray layout.topLeftLabel slot.caption
    ]


drawDate : Layout -> Maybe String -> List Ui.RenderOp
drawDate layout maybeDate =
    case maybeDate of
        Nothing ->
            []

        Just value ->
            [ textAt Color.white layout.topRightDate value ]


drawWeatherCorner : Layout -> Maybe String -> List Ui.RenderOp
drawWeatherCorner layout maybeLabel =
    case maybeLabel of
        Nothing ->
            []

        Just label ->
            [ textAt Color.white layout.bottomLeftWeather label ]


drawBottomRight : Layout -> BottomRightSlot -> List Ui.RenderOp
drawBottomRight layout slot =
    case slot of
        AltitudeSlot value ->
            [ Ui.drawVectorAt Resources.VectorStaticMountain layout.bottomRight.vector
            , textAt Color.white layout.bottomRight.singleLine value
            ]

        SimpleLine value ->
            [ textAt Color.white layout.bottomRight.singleLine value ]

        CountdownSlot label timeLine ->
            drawBottomRightCountdown layout label timeLine


drawBottomRightCountdown : Layout -> String -> String -> List Ui.RenderOp
drawBottomRightCountdown layout label timeLine =
    let
        br =
            layout.bottomRight

        labelH =
            br.countdownLabelH

        timeH =
            br.countdownTimeH

        topY =
            br.bottom - labelH - timeH

        labelY =
            topY - 2

        labelRect =
            { x = br.x, y = labelY, w = br.textW, h = labelH }

        timeRect =
            { x = br.x, y = topY + labelH - 1, w = br.textW, h = timeH }
    in
    [ textAt Color.lightGray labelRect label
    , textAt Color.white timeRect timeLine
    ]


defaultSunWindow : SunWindow
defaultSunWindow =
    { sunriseMin = 360
    , sunsetMin = 1080
    , mode = SunCycle
    }


textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAt color bounds value =
    Ui.group
        (Ui.context
            [ Ui.textColor color ]
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions bounds value ]
        )


pointAt : Int -> Int -> Int -> Int -> Ui.Point
pointAt cx cy radius angle =
    let
        theta =
            toFloat angle * 2 * Basics.pi / 65536
    in
    { x = cx + round (sin theta * toFloat radius)
    , y = cy - round (cos theta * toFloat radius)
    }


angleFromMinute : Int -> Int
angleFromMinute minute =
    modBy 65536 (((minute - 720) * 65536) // 1440)
