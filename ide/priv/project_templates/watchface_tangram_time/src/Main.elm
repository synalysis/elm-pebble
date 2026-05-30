module Main exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Cmd as PebbleCmd
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui exposing (Point)
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { now : Maybe PebbleCmd.CurrentDateTime
    , screenW : Int
    , screenH : Int
    , colorMode : Platform.ColorCapability
    , companionFigure : Maybe Int
    , downloadedPieces : List DownloadedPiece
    , pendingFigure : Maybe PendingFigure
    }


type alias DownloadedPiece =
    { index : Int
    , vertexCount : Int
    , p1 : Point
    , p2 : Point
    , p3 : Point
    , p4 : Point
    }


type alias PendingFigure =
    { figureId : Int
    , pieces : List DownloadedPiece
    }


type alias Rect =
    { x : Int
    , y : Int
    , w : Int
    , h : Int
    }


type Msg
    = CurrentDateTime PebbleCmd.CurrentDateTime
    | MinuteChanged Int
    | FromPhone PhoneToWatch


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { now = Nothing
      , screenW = context.screen.width
      , screenH = context.screen.height
      , colorMode = context.screen.colorMode
      , companionFigure = Nothing
      , downloadedPieces = []
      , pendingFigure = Nothing
      }
    , Cmd.batch
        [ PebbleCmd.getCurrentDateTime CurrentDateTime
        , CompanionWatch.sendWatchToPhone RequestFigure
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( { model | now = Just value }, Cmd.none )

        MinuteChanged _ ->
            ( model
            , PebbleCmd.getCurrentDateTime CurrentDateTime
            )

        FromPhone (ProvideFigure figureId) ->
            ( { model | companionFigure = Just (modBy figureCount figureId), downloadedPieces = [], pendingFigure = Nothing }, Cmd.none )

        FromPhone (BeginFigure figureId) ->
            ( { model | companionFigure = Just figureId, pendingFigure = Just { figureId = figureId, pieces = [] } }, Cmd.none )

        FromPhone (ProvidePiece figureId pieceIndex vertexCount x1 y1 x2 y2 x3 y3 x4 y4) ->
            ( addDownloadedPiece figureId
                { index = pieceIndex
                , vertexCount = vertexCount
                , p1 = o x1 y1
                , p2 = o x2 y2
                , p3 = o x3 y3
                , p4 = o x4 y4
                }
                model
            , Cmd.none
            )

        FromPhone (EndFigure figureId) ->
            ( finishDownloadedFigure figureId model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Events.onMinuteChange MinuteChanged
        , CompanionWatch.onPhoneToWatch FromPhone
        ]


view : Model -> Ui.UiNode
view model =
    let
        cx =
            model.screenW // 2

        cy =
            model.screenH // 2

        hour =
            currentHour model

        minute =
            currentMinute model

        scale =
            layoutScale model

        clockRadius =
            scaled scale 60

        markerRadius =
            scaled scale 68

        hourRadius =
            scaled scale 42

        minuteRadius =
            scaled scale 66

        figure =
            case model.companionFigure of
                Just companionFigure ->
                    companionFigure

                Nothing ->
                    minute
    in
    List.concat
        [ [ Ui.clear (backgroundColor model)
          , Ui.circle { x = cx, y = cy } clockRadius (clockColor model)
          ]
        , hourMarkers cx cy markerRadius (foregroundColor model)
        , case model.downloadedPieces of
            [] ->
                [ builtInFigure scale cx cy hour minute figure ]

            pieces ->
                downloadedTangram model.colorMode scale cx cy hour minute figure pieces
        , [ Ui.fillCircle (clockPoint cx cy hour hourRadius) 4 (accentColor model)
          , Ui.fillCircle (minutePoint cx cy minute minuteRadius) 3 (accentColor model)
          ]
        , timeText model scale cx cy hour minute figure
        ]
        |> Ui.toUiNode


figureVector : Int -> Resources.StaticVector
figureVector figure =
    case modBy figureCount figure of
        0 ->
            Resources.VectorStaticTangramBird

        1 ->
            Resources.VectorStaticTangramComet

        2 ->
            Resources.VectorStaticTangramCrown

        3 ->
            Resources.VectorStaticTangramBoat

        4 ->
            Resources.VectorStaticTangramFlower

        _ ->
            Resources.VectorStaticTangramKite


figureOriginOffsetX : Int
figureOriginOffsetX =
    66


figureOriginOffsetY : Int
figureOriginOffsetY =
    58


vectorDrawOrigin : Int -> Point -> Point
vectorDrawOrigin scale base =
    { x = base.x - scaled scale figureOriginOffsetX
    , y = base.y - scaled scale figureOriginOffsetY
    }


builtInFigure : Int -> Int -> Int -> Int -> Int -> Int -> Ui.RenderOp
builtInFigure scale cx cy hour minute figure =
    let
        base =
            formOrigin scale cx cy hour minute figure

        origin =
            vectorDrawOrigin scale base
    in
    Ui.drawVectorAt (figureVector figure) origin


downloadedTangram : Platform.ColorCapability -> Int -> Int -> Int -> Int -> Int -> Int -> List DownloadedPiece -> List Ui.RenderOp
downloadedTangram colorMode scale cx cy hour minute figure pieces =
    let
        base =
            formOrigin scale cx cy hour minute figure
    in
    pieces
        |> List.reverse
        |> List.concatMap (\piece -> tangramPiece (displayColor colorMode (pieceColor piece.index)) (shapeAt scale base (piecePoints piece)))


piecePoints : DownloadedPiece -> List Point
piecePoints piece =
    if piece.vertexCount == 3 then
        [ piece.p1, piece.p2, piece.p3 ]
    else
        [ piece.p1, piece.p2, piece.p3, piece.p4 ]


pieceColor : Int -> Color.Color
pieceColor index =
    case modBy 7 index of
        0 ->
            Color.vividCerulean

        1 ->
            Color.pictonBlue

        2 ->
            Color.tiffanyBlue

        3 ->
            Color.cyan

        4 ->
            Color.blueMoon

        5 ->
            Color.electricBlue

        _ ->
            Color.veryLightBlue


backgroundColor : Model -> Color.Color
backgroundColor model =
    if Platform.colorCapabilityIsColor model.colorMode then
        Color.oxfordBlue
    else
        Color.white


foregroundColor : Model -> Color.Color
foregroundColor model =
    if Platform.colorCapabilityIsColor model.colorMode then
        Color.white
    else
        Color.black


clockColor : Model -> Color.Color
clockColor model =
    if Platform.colorCapabilityIsColor model.colorMode then
        Color.veryLightBlue
    else
        Color.black


accentColor : Model -> Color.Color
accentColor model =
    if Platform.colorCapabilityIsColor model.colorMode then
        Color.chromeYellow
    else
        Color.black


displayColor : Platform.ColorCapability -> Color.Color -> Color.Color
displayColor colorMode color =
    if Platform.colorCapabilityIsColor colorMode then
        color
    else
        Color.black


tangramPiece : Color.Color -> List Point -> List Ui.RenderOp
tangramPiece color points =
    polygonLines color points
        ++ hatchLines color points


polygonLines : Color.Color -> List Point -> List Ui.RenderOp
polygonLines color points =
    case points of
        a :: b :: c :: [] ->
            [ Ui.line a b color, Ui.line b c color, Ui.line c a color ]

        a :: b :: c :: d :: [] ->
            [ Ui.line a b color, Ui.line b c color, Ui.line c d color, Ui.line d a color ]

        _ ->
            []


hatchLines : Color.Color -> List Point -> List Ui.RenderOp
hatchLines color points =
    case points of
        a :: b :: c :: [] ->
            [ Ui.line (midpoint a b) (midpoint a c) color
            , Ui.line (midpoint b a) (midpoint b c) color
            , Ui.line (midpoint c a) (midpoint c b) color
            ]

        a :: b :: c :: d :: [] ->
            [ Ui.line (midpoint a b) (midpoint d c) color
            , Ui.line (midpoint a d) (midpoint b c) color
            ]

        _ ->
            []


shapeAt : Int -> Point -> List Point -> List Point
shapeAt scale anchor points =
    List.map (\point -> { x = anchor.x + scaled scale point.x, y = anchor.y + scaled scale point.y }) points


nudgePoint : Point -> Point -> Point
nudgePoint point nudge =
    { x = point.x + nudge.x, y = point.y + nudge.y }


scalePoint : Int -> Point -> Point
scalePoint scale point =
    { x = scaled scale point.x, y = scaled scale point.y }


scaled : Int -> Int -> Int
scaled scale value =
    (value * scale) // 100


layoutScale : Model -> Int
layoutScale model =
    clampInt 100 130 ((min model.screenW model.screenH * 100) // 156)


o : Int -> Int -> Point
o x y =
    { x = x, y = y }


midpoint : Point -> Point -> Point
midpoint a b =
    { x = (a.x + b.x) // 2, y = (a.y + b.y) // 2 }


p : Int -> Int -> Int -> Int -> Point
p cx cy x y =
    { x = cx + x, y = cy + y }


formOrigin : Int -> Int -> Int -> Int -> Int -> Int -> Point
formOrigin scale cx cy hour minute figure =
    let
        drift =
            scalePoint scale (minuteNudge minute)

        clearanceDrift =
            case minute // 15 of
                0 ->
                    scalePoint scale (o 0 8)

                1 ->
                    scalePoint scale (o -8 0)

                2 ->
                    scalePoint scale (o 0 -8)

                _ ->
                    scalePoint scale (o 8 0)

        hourDrift =
            case modBy 4 hour of
                0 ->
                    scalePoint scale (o -2 -1)

                1 ->
                    scalePoint scale (o 2 -1)

                2 ->
                    scalePoint scale (o 2 1)

                _ ->
                    scalePoint scale (o -2 1)

        figureDrift =
            scalePoint scale (figureNudge figure)
    in
    nudgePoint (nudgePoint (nudgePoint (nudgePoint (p cx cy 0 (scaled scale -20)) clearanceDrift) drift) hourDrift) figureDrift


currentHour : Model -> Int
currentHour model =
    case model.now of
        Just value ->
            modBy 12 value.hour

        Nothing ->
            0


currentMinute : Model -> Int
currentMinute model =
    case model.now of
        Just value ->
            value.minute

        Nothing ->
            0


addDownloadedPiece : Int -> DownloadedPiece -> Model -> Model
addDownloadedPiece figureId piece model =
    case model.pendingFigure of
        Just pending ->
            if pending.figureId == figureId then
                { model | pendingFigure = Just { pending | pieces = piece :: pending.pieces } }
            else
                model

        Nothing ->
            model


finishDownloadedFigure : Int -> Model -> Model
finishDownloadedFigure figureId model =
    case model.pendingFigure of
        Just pending ->
            if pending.figureId == figureId && List.length pending.pieces >= 7 then
                { model | downloadedPieces = pending.pieces, pendingFigure = Nothing }
            else
                { model | pendingFigure = Nothing }

        Nothing ->
            model


figureCount : Int
figureCount =
    6


figureNudge : Int -> Point
figureNudge figure =
    case modBy 8 (figure // figureCount) of
        0 ->
            o 0 0

        1 ->
            o 6 -4

        2 ->
            o -6 -4

        3 ->
            o 8 3

        4 ->
            o -8 3

        5 ->
            o 4 7

        6 ->
            o -4 7

        _ ->
            o 0 -8


minutePoint : Int -> Int -> Int -> Int -> Point
minutePoint cx cy minute radius =
    let
        slot =
            minute // 5

        fine =
            modBy 5 minute

        start =
            clockPoint cx cy slot radius

        finish =
            clockPoint cx cy (slot + 1) radius
    in
    { x = start.x + ((finish.x - start.x) * fine) // 5
    , y = start.y + ((finish.y - start.y) * fine) // 5
    }


minuteAnchor : Int -> Int -> Int -> Int -> Int -> Point
minuteAnchor cx cy minute offset radius =
    nudgePoint (clockPoint cx cy ((minute // 5) + offset) radius) (minuteNudge minute)


minuteNudge : Int -> Point
minuteNudge minute =
    case modBy 5 minute of
        0 ->
            o 0 0

        1 ->
            o 3 -1

        2 ->
            o 4 1

        3 ->
            o 2 3

        _ ->
            o -1 4


clockPoint : Int -> Int -> Int -> Int -> Point
clockPoint cx cy slot radius =
    let
        scaled =
            radius // 2
    in
    case modBy 12 slot of
        0 ->
            p cx cy 0 (0 - radius)

        1 ->
            p cx cy scaled (0 - radius)

        2 ->
            p cx cy radius (0 - scaled)

        3 ->
            p cx cy radius 0

        4 ->
            p cx cy radius scaled

        5 ->
            p cx cy scaled radius

        6 ->
            p cx cy 0 radius

        7 ->
            p cx cy (0 - scaled) radius

        8 ->
            p cx cy (0 - radius) scaled

        9 ->
            p cx cy (0 - radius) 0

        10 ->
            p cx cy (0 - radius) (0 - scaled)

        _ ->
            p cx cy (0 - scaled) (0 - radius)


hourMarkers : Int -> Int -> Int -> Color.Color -> List Ui.RenderOp
hourMarkers cx cy radius color =
    [ Ui.fillCircle (clockPoint cx cy 0 radius) 2 color
    , Ui.fillCircle (clockPoint cx cy 3 radius) 2 color
    , Ui.fillCircle (clockPoint cx cy 6 radius) 2 color
    , Ui.fillCircle (clockPoint cx cy 9 radius) 2 color
    ]


timeText : Model -> Int -> Int -> Int -> Int -> Int -> Int -> List Ui.RenderOp
timeText model scale cx cy hour minute figure =
    let
        label =
            case model.now of
                Just value ->
                    pad2 value.hour ++ ":" ++ pad2 value.minute

                Nothing ->
                    "--:--"

        position =
            timeTextPosition model.screenW model.screenH scale cx cy hour minute figure
    in
    [ Ui.group
        (Ui.context
            [ Ui.textColor (foregroundColor model) ]
            [ Ui.text Resources.DefaultFont (Ui.alignCenter Ui.defaultTextOptions) { x = position.x, y = position.y, w = timeTextWidth, h = timeTextHeight } label ]
        )
    ]


timeTextWidth : Int
timeTextWidth =
    72


timeTextHeight : Int
timeTextHeight =
    22


timeTextPosition : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Point
timeTextPosition screenW screenH scale cx cy hour minute figure =
    let
        hourRadius =
            scaled scale 42

        minuteRadius =
            scaled scale 66

        markerRadius =
            scaled scale 68

        candidates =
            [ o 8 (cy + 24)
            , o (screenW - timeTextWidth - 8) (cy + 24)
            , o 16 (cy + 44)
            , o (screenW - timeTextWidth - 16) (cy + 44)
            , o (cx - 72) (cy - 58)
            , o cx (cy - 58)
            , o 8 (cy - 12)
            , o (screenW - timeTextWidth - 8) (cy - 12)
            ]

        hourMarker =
            clockPoint cx cy hour hourRadius

        minuteMarker =
            minutePoint cx cy minute minuteRadius

        figureRect =
            tangramBounds scale (formOrigin scale cx cy hour minute figure)
    in
    bestTextCandidate cy hourMarker minuteMarker (clockPoint cx cy 0 markerRadius) (clockPoint cx cy 3 markerRadius) (clockPoint cx cy 6 markerRadius) (clockPoint cx cy 9 markerRadius) figureRect candidates
        |> clampTextPosition screenW screenH


bestTextCandidate : Int -> Point -> Point -> Point -> Point -> Point -> Point -> Rect -> List Point -> Point
bestTextCandidate cy hourMarker minuteMarker topMarker rightMarker bottomMarker leftMarker figureRect candidates =
    case candidates of
        first :: rest ->
            List.foldl
                (\candidate best ->
                    if textCandidateScore cy hourMarker minuteMarker topMarker rightMarker bottomMarker leftMarker figureRect candidate < textCandidateScore cy hourMarker minuteMarker topMarker rightMarker bottomMarker leftMarker figureRect best then
                        candidate
                    else
                        best
                )
                first
                rest

        [] ->
            o 0 0


textCandidateScore : Int -> Point -> Point -> Point -> Point -> Point -> Point -> Rect -> Point -> Int
textCandidateScore cy hourMarker minuteMarker topMarker rightMarker bottomMarker leftMarker figureRect position =
    let
        rect =
            { x = position.x, y = position.y, w = timeTextWidth, h = timeTextHeight }

        handPenalty =
            pointPenalty 10 hourMarker.x hourMarker.y rect.x rect.y rect.w rect.h
                + pointPenalty 10 minuteMarker.x minuteMarker.y rect.x rect.y rect.w rect.h

        fixedMarkerPenalty =
            pointPenalty 12 topMarker.x topMarker.y rect.x rect.y rect.w rect.h
                + pointPenalty 12 rightMarker.x rightMarker.y rect.x rect.y rect.w rect.h
                + pointPenalty 12 bottomMarker.x bottomMarker.y rect.x rect.y rect.w rect.h
                + pointPenalty 12 leftMarker.x leftMarker.y rect.x rect.y rect.w rect.h

        figurePenalty =
            rectOverlapPenalty (rect.x - 4) (rect.y - 4) (rect.w + 8) (rect.h + 8) figureRect.x figureRect.y figureRect.w figureRect.h

        lowerBias =
            if position.y >= cy then
                -25
            else
                0
    in
    handPenalty + fixedMarkerPenalty + figurePenalty + lowerBias


pointPenalty : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int
pointPenalty clearance pointX pointY rectX rectY rectW rectH =
    if pointX >= rectX - clearance && pointX <= rectX + rectW + clearance && pointY >= rectY - clearance && pointY <= rectY + rectH + clearance then
        260
    else
        0


rectOverlapPenalty : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int
rectOverlapPenalty ax ay aw ah bx by bw bh =
    if ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by then
        120
    else
        0


tangramBounds : Int -> Point -> Rect
tangramBounds scale origin =
    { x = origin.x - scaled scale figureOriginOffsetX
    , y = origin.y - scaled scale figureOriginOffsetY
    , w = scaled scale (figureOriginOffsetX * 2)
    , h = scaled scale (figureOriginOffsetY + 68)
    }


clampTextPosition : Int -> Int -> Point -> Point
clampTextPosition screenW screenH position =
    { x = clampInt 8 (screenW - timeTextWidth - 8) position.x
    , y = clampInt 8 (screenH - timeTextHeight - 8) position.y
    }


clampInt : Int -> Int -> Int -> Int
clampInt low high value =
    max low (min high value)


pad2 : Int -> String
pad2 value =
    if value < 10 then
        "0" ++ String.fromInt value
    else
        String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
