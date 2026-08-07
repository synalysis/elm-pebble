module Yes.Render exposing (CornerSlots, FaceDisplay, SunWindow, WeatherSlot, face)

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
    , moonriseMin : Maybe Int
    , moonsetMin : Maybe Int
    , moonPhaseE6 : Maybe Int
    , corners : CornerSlots
    }


type alias WeatherSlot =
    { label : String
    , icon : Resources.StaticVector
    }


type alias CornerSlots =
    { topLeft : { value : String, icon : Resources.StaticVector }
    , date : Maybe String
    , weather : Maybe WeatherSlot
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

        moonArc =
            case ( display.moonriseMin, display.moonsetMin ) of
                ( Just rise, Just set ) ->
                    coloredRadialWedge moonBounds
                        Color.blueMoon
                        (angleFromMinute rise)
                        (angleFromMinute set)

                _ ->
                    []
    in
    [ Ui.fillCircle center layout.outerRadius Color.oxfordBlue ]
        ++ moonArc
        ++ [ Ui.fillCircle center layout.innerRadius Color.black ]
        ++ (if hasSunData then
                drawSunWindow center layout.innerRadius sunBounds sunriseAngle sunsetAngle sunWindow

            else
                []
           )
        ++ [ Ui.circle center layout.outerRadius Color.white
           , Ui.circle center layout.innerRadius Color.darkGray
           ]
        ++ drawOuterScale layout
        ++ draw24HourHand layout display.homeMinute
        ++ drawMoonGlyph layout display.moonPhaseE6
        ++ [ textAt Color.black layout.timeTextBand display.timeText ]


draw24HourHand : Layout -> Int -> List Ui.RenderOp
draw24HourHand layout nowMin =
    let
        handAngle =
            angleFromMinute nowMin

        tip =
            pointAt layout.cx layout.cy layout.handLen handAngle
    in
    [ Ui.line { x = layout.cx, y = layout.cy } tip Color.white
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
                    { x = labelPoint.x - 9, y = labelPoint.y - 12, w = 18, h = 12 }
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
        -- Wrapped wedge as one op (end = endAngle + 65536) so firmware can fill
        -- across noon without a seam between two meeting gpaths.
        coloredRadial bounds color startAngle (endAngle + 65536)

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


drawMoonGlyph : Layout -> Maybe Int -> List Ui.RenderOp
drawMoonGlyph layout maybePhase =
    case maybePhase of
        Just phaseE6 ->
            drawMoonPhase layout phaseE6

        Nothing ->
            let
                center =
                    { x = layout.cx, y = layout.moonY }
            in
            [ Ui.fillCircle center layout.moonPhaseRadius Color.black
            , Ui.circle center layout.moonPhaseRadius Color.white
            ]


{-| Northern-hemisphere style disk from `phaseE6` (0 = new, 500000 ≈ full).
-}
drawMoonPhase : Layout -> Int -> List Ui.RenderOp
drawMoonPhase layout phaseE6 =
    let
        center =
            { x = layout.cx, y = layout.moonY }

        r =
            layout.moonPhaseRadius

        bounds =
            { x = center.x - r, y = center.y - r, w = r * 2, h = r * 2 }

        phase =
            clamp 0 1000000 phaseE6

        -- Cycle fraction 0..1; illumination 0 at new, 1 at full.
        turn =
            toFloat phase / 1000000

        illum =
            (1 - cos (turns turn)) / 2

        waxing =
            phase < 500000

        -- Terminator offset: 0 near quarters, ±r near new/full.
        offset =
            round (toFloat r * cos (turns turn))
    in
    if abs (phase - 500000) <= 20000 then
        [ Ui.fillCircle center r Color.lightGray
        , Ui.circle center r Color.white
        ]

    else if phase <= 20000 || phase >= 980000 then
        [ Ui.fillCircle center r Color.black
        , Ui.circle center r Color.white
        ]

    else
        let
            litHalf =
                if waxing then
                    -- Right half lit while waxing.
                    coloredRadial bounds Color.lightGray 0 32768

                else
                    -- Left half lit while waning.
                    coloredRadial bounds Color.lightGray 32768 65536

            overlay =
                if abs offset < max 1 (r // 8) then
                    []

                else if illum < 0.5 then
                    -- Crescent: dark disk eats the lit half.
                    [ Ui.fillCircle { x = center.x + offset, y = center.y } r Color.black ]

                else
                    -- Gibbous: lit disk fills past the half.
                    [ Ui.fillCircle { x = center.x + offset, y = center.y } r Color.lightGray ]
        in
        [ Ui.fillCircle center r Color.black ]
            ++ litHalf
            ++ overlay
            ++ [ Ui.circle center r Color.white ]


drawCorners : Layout -> CornerSlots -> List Ui.RenderOp
drawCorners layout slots =
    drawTopLeft layout slots.topLeft
        ++ drawDate layout slots.date
        ++ drawWeatherCorner layout slots.weather
        ++ drawBottomRight layout slots.bottomRight


drawTopLeft : Layout -> { value : String, icon : Resources.StaticVector } -> List Ui.RenderOp
drawTopLeft layout slot =
    [ textAt Color.white layout.topLeftTitle slot.value
    , Ui.drawVectorAt slot.icon layout.topLeftIcon
    ]


drawDate : Layout -> Maybe String -> List Ui.RenderOp
drawDate layout maybeDate =
    case maybeDate of
        Nothing ->
            []

        Just value ->
            [ textAtRight Color.white layout.topRightDate value ]


drawWeatherCorner : Layout -> Maybe WeatherSlot -> List Ui.RenderOp
drawWeatherCorner layout maybeSlot =
    case maybeSlot of
        Nothing ->
            []

        Just slot ->
            [ Ui.drawVectorAt slot.icon layout.bottomLeftWeatherVector
            , textAtLeft Color.white layout.bottomLeftWeather slot.label
            ]


drawBottomRight : Layout -> BottomRightSlot -> List Ui.RenderOp
drawBottomRight layout slot =
    case slot of
        AltitudeSlot value ->
            [ Ui.drawVectorAt Resources.VectorStaticMountain layout.bottomRight.vector
            , textAtRight Color.white layout.bottomRight.singleLine value
            ]

        SimpleLine value ->
            [ textAtRight Color.white layout.bottomRight.singleLine value ]

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
    [ textAtRight Color.lightGray labelRect label
    , textAtRight Color.white timeRect timeLine
    ]


defaultSunWindow : SunWindow
defaultSunWindow =
    { sunriseMin = 360
    , sunsetMin = 1080
    , mode = SunCycle
    }


textAt : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAt color bounds value =
    textAtOptions Ui.defaultTextOptions color bounds value


textAtLeft : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAtLeft color bounds value =
    textAtOptions (Ui.defaultTextOptions |> Ui.alignLeft) color bounds value


textAtRight : Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAtRight color bounds value =
    textAtOptions (Ui.defaultTextOptions |> Ui.alignRight) color bounds value


textAtOptions : Ui.TextOptions -> Color.Color -> Ui.Rect -> String -> Ui.RenderOp
textAtOptions options color bounds value =
    Ui.group
        (Ui.context
            [ Ui.textColor color ]
            [ Ui.text Resources.DefaultFont options bounds value ]
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
