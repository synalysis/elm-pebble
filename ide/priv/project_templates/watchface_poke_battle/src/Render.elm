module Render exposing (FaceModel, render)

import Battle exposing (Scene(..))
import Pokemon exposing (Attack(..), Opponent, Player, attackName, speciesName)
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Layout =
    { screenW : Int
    , screenH : Int
    , boxX : Int
    , boxY : Int
    , arcStart : Int
    , arcEnd : Int
    }


type alias FaceModel =
    { layout : Layout
    , scene : Scene
    , player : Player
    , opponent : Opponent
    , opponentHealth : Float
    , opponentYOffset : Int
    , batteryPercent : Int
    , showDate : Bool
    , showSteps : Bool
    , stepsToday : Maybe Int
    , hour : Int
    , minute : Int
    , month : Int
    , day : Int
    , use24Hour : Bool
    , thunderFlash : Bool
    }


layoutFor : Int -> Int -> Layout
layoutFor screenW screenH =
    { screenW = screenW
    , screenH = screenH
    , boxX = 3 * screenW // 24
    , boxY = 19 * screenH // 24
    , arcStart =
        if screenW > 240 then
            224

        else
            225
    , arcEnd =
        if screenW > 240 then
            316

        else
            315
    }


render : FaceModel -> List Ui.RenderOp
render model =
    let
        layout =
            model.layout
    in
    [ Ui.clear (if model.thunderFlash then Color.white else Color.black) ]
        ++ drawTime layout model
        ++ (if model.showDate then
                drawDate layout model

            else
                []
           )
        ++ (if model.showSteps then
                drawSteps layout model

            else
                []
           )
        ++ drawPlayer layout model
        ++ drawInfoBox layout
        ++ drawScene layout model


drawTime : Layout -> FaceModel -> List Ui.RenderOp
drawTime layout model =
    let
        displayHour =
            if model.use24Hour then
                model.hour

            else if model.hour > 12 || model.hour == 0 then
                if model.hour == 0 then
                    12

            else
                model.hour - 12

            else
                model.hour
    in
    [ textCentered layout.screenW (18 * layout.screenH // 240) 80 28 (pad2 displayHour ++ ":" ++ pad2 model.minute) ]


drawDate : Layout -> FaceModel -> List Ui.RenderOp
drawDate layout model =
    [ textCentered layout.screenW (8 * layout.screenH // 240) 80 16 (String.fromInt model.month ++ " " ++ String.fromInt model.day) ]


drawSteps : Layout -> FaceModel -> List Ui.RenderOp
drawSteps layout model =
    case model.stepsToday of
        Just steps ->
            [ textCentered layout.screenW (40 * layout.screenH // 240) 80 16 (String.fromInt steps) ]

        Nothing ->
            []


drawInfoBox : Layout -> List Ui.RenderOp
drawInfoBox layout =
    let
        cx =
            layout.screenW // 2

        cy =
            layout.screenH // 2

        radius =
            layout.screenW // 2 - 4

        innerRadius =
            layout.screenW // 2 - 6

        ballW =
            12

        ballH =
            12
    in
    [ Ui.group
        (Ui.context [ Ui.strokeColor Color.white, Ui.strokeWidth 2 ]
            [ Ui.arc (square cx cy radius) layout.arcStart layout.arcEnd
            , Ui.line { x = layout.boxX + ballW, y = layout.boxY + ballH // 2 + 1 }
                { x = layout.screenW - layout.boxX - ballW, y = layout.boxY + ballH // 2 + 1 }
            ]
        )
    , Ui.group
        (Ui.context [ Ui.strokeColor Color.white, Ui.strokeWidth 1 ]
            [ Ui.arc (square cx cy innerRadius) layout.arcStart layout.arcEnd
            , Ui.line { x = layout.boxX + ballW - 1, y = layout.boxY + ballH // 2 - 2 }
                { x = layout.screenW - layout.boxX - ballW + 1, y = layout.boxY + ballH // 2 - 2 }
            ]
        )
    , Ui.drawBitmapInRect Resources.BitmapStaticBoxBall { x = layout.boxX, y = layout.boxY, w = ballW, h = ballH }
    , Ui.drawBitmapInRect Resources.BitmapStaticBoxBall
        { x = layout.screenW - layout.boxX - ballW
        , y = layout.boxY
        , w = ballW
        , h = ballH
        }
    ]


drawPlayer : Layout -> FaceModel -> List Ui.RenderOp
drawPlayer layout model =
    let
        namePos =
            if layout.screenW > 240 then
                ( layout.screenW // 2 - 10, layout.screenH // 2 + 20 )

            else
                ( layout.screenW // 2 - 15, layout.screenH // 2 + 20 )

        ( nameX, nameY ) =
            namePos

        player =
            model.player
    in
    drawTrainerCard layout nameX nameY player.displayName player.levelTag model.batteryPercent False
        ++ [ Ui.drawBitmapInRect player.bitmap { x = player.x, y = player.y, w = 56, h = 48 } ]


drawScene : Layout -> FaceModel -> List Ui.RenderOp
drawScene layout model =
    case model.scene of
        Waiting ->
            drawPokeball layout model.opponent

        WildAppears _ ->
            drawOpponent layout model
                ++ drawOpeningPokeball layout model.opponent
                ++ dialog layout
                    [ "A wild " ++ speciesName model.opponent.species
                    , "appeared!"
                    ]

        OpponentShown _ ->
            drawOpponent layout model

        AttackAnnounce _ ->
            drawOpponent layout model
                ++ dialog layout
                    [ model.player.displayName ++ " used"
                    , attackName model.player.attack ++ "!"
                    ]

        AttackFrame1 ->
            drawOpponent layout model
                ++ drawAttack layout model 1
                ++ dialog layout
                    [ model.player.displayName ++ " used"
                    , attackName model.player.attack ++ "!"
                    ]

        AttackFrame2 ->
            drawOpponent layout model
                ++ drawAttack layout model 2
                ++ dialog layout
                    [ model.player.displayName ++ " used"
                    , attackName model.player.attack ++ "!"
                    ]

        AttackFrame3 ->
            drawOpponent layout model
                ++ drawAttack layout model 3
                ++ dialog layout
                    [ model.player.displayName ++ " used"
                    , attackName model.player.attack ++ "!"
                    ]

        HealthDrain ->
            drawOpponent layout model

        FaintSlide ->
            drawOpponent layout model
                ++ eraseBelowOpponent layout model.opponent

        Fainted _ ->
            dialog layout
                [ "Enemy " ++ speciesName model.opponent.species
                , "fainted!"
                ]

        Victory _ ->
            dialog layout [ "Victory!" ]

        Done ->
            drawPokeball layout model.opponent


drawPokeball : Layout -> Opponent -> List Ui.RenderOp
drawPokeball layout foe =
    [ Ui.drawBitmapInRect Resources.BitmapStaticPokeball
        { x = foe.x, y = foe.y + 35, w = 24, h = 24 }
    ]


drawOpeningPokeball : Layout -> Opponent -> List Ui.RenderOp
drawOpeningPokeball layout foe =
    [ Ui.drawBitmapInRect Resources.BitmapStaticPokeballOpen
        { x = foe.x + 10, y = foe.y + 35, w = 24, h = 24 }
    ]


drawOpponent : Layout -> FaceModel -> List Ui.RenderOp
drawOpponent layout model =
    let
        foe =
            model.opponent

        ( nameX, nameY ) =
            if layout.screenW > 240 then
                ( 27, layout.screenH // 4 + 5 )

            else
                ( 17, layout.screenH // 4 + 5 )
    in
    drawTrainerCard layout nameX nameY (speciesName foe.species) foe.levelTag model.opponentHealth True
        ++ [ Ui.drawBitmapInRect foe.bitmap
                { x = foe.x
                , y = foe.y + model.opponentYOffset
                , w = 56
                , h = 48
                }
           ]


drawTrainerCard : Layout -> Int -> Int -> String -> String -> Float -> Bool -> List Ui.RenderOp
drawTrainerCard layout nameX nameY name levelTag health isOpponent =
    let
        barW =
            healthBarWidth health

        barColor =
            healthColor health
    in
    [ textLeft nameX nameY 72 16 (String.toUpper name)
    , textLeft (nameX + 28) (nameY + 15) 40 12 levelTag
    , textLeft (nameX + 3) (nameY + 30) 24 10 "HP:"
    , Ui.drawBitmapInRect Resources.BitmapStaticHealthEmpty { x = nameX + 27, y = nameY + 32, w = 48, h = 8 }
    , Ui.group
        (Ui.context [ Ui.fillColor barColor ]
            [ Ui.fillRect { x = nameX + 29, y = nameY + 34, w = barW, h = 2 } barColor ]
        )
    ]
        ++ (if isOpponent then
                []

            else
                []
           )


healthBarWidth : Float -> Int
healthBarWidth health =
    let
        fillable =
            42
    in
    if health <= 0.1 then
        0

    else
        round (toFloat fillable * health) + 2


healthColor : Float -> Color.Color
healthColor health =
    if health > 0.5 then
        Color.green

    else if health > 0.21 then
        Color.chromeYellow

    else
        Color.red


drawAttack : Layout -> FaceModel -> Int -> List Ui.RenderOp
drawAttack layout model frame =
    case model.player.attack of
        Thunder ->
            drawThunder layout model.opponent

        Psywave ->
            drawPsywave layout model.player frame

        Ember ->
            drawEmbers layout model.opponent frame

        Bubble ->
            drawBubbles layout model.player frame


drawThunder : Layout -> Opponent -> List Ui.RenderOp
drawThunder layout foe =
    let
        centerX =
            foe.x + 28

        centerY =
            foe.y + 24
    in
    [ Ui.group
        (Ui.context [ Ui.fillColor Color.chromeYellow ]
            [ Ui.fillCircle { x = centerX, y = centerY } 12 Color.chromeYellow ]
        )
    , Ui.drawBitmapInRect Resources.BitmapStaticThunderbolts { x = centerX - 14, y = centerY - 16, w = 28, h = 32 }
    ]


drawPsywave : Layout -> Player -> Int -> List Ui.RenderOp
drawPsywave layout player frame =
    let
        baseX =
            player.x + 56

        baseY =
            player.y
    in
    (if frame >= 1 then
        [ psyEllipse (baseX - 10) baseY 7 13
        , psyEllipse (baseX + 5) (baseY + 12) 7 13
        ]

     else
        []
    )
        ++ (if frame >= 2 then
                [ psyEllipse (baseX + 50) (baseY - 40) 13 22
                , psyEllipse (baseX + 65) (baseY - 28) 13 22
                , psyEllipse (baseX + 22) (baseY - 20) 10 22
                , psyEllipse (baseX + 37) (baseY - 8) 10 22
                ]

            else
                []
           )
        ++ (if frame >= 3 then
                []

            else
                []
           )


psyEllipse : Int -> Int -> Int -> Int -> Ui.RenderOp
psyEllipse x y radX radY =
    Ui.group
        (Ui.context
            [ Ui.strokeColor Color.folly, Ui.strokeWidth 4 ]
            [ Ui.circle { x = x + radX, y = y + radY } (max radX radY) Color.folly ]
        )


drawEmbers : Layout -> Opponent -> Int -> List Ui.RenderOp
drawEmbers layout foe frame =
    let
        y =
            foe.y + 48
    in
    case frame of
        1 ->
            [ Ui.drawBitmapInRect Resources.BitmapStaticEmberSmall { x = foe.x, y = y - 20, w = 16, h = 20 }
            , Ui.drawBitmapInRect Resources.BitmapStaticEmberSmall { x = foe.x + 25, y = y - 20, w = 16, h = 20 }
            ]

        2 ->
            [ Ui.drawBitmapInRect Resources.BitmapStaticEmberBig { x = foe.x, y = y - 24, w = 16, h = 24 }
            , Ui.drawBitmapInRect Resources.BitmapStaticEmberBig { x = foe.x + 25, y = y - 24, w = 16, h = 24 }
            ]

        _ ->
            [ Ui.drawBitmapInRect Resources.BitmapStaticEmberSmall { x = foe.x, y = y - 20, w = 16, h = 20 }
            , Ui.drawBitmapInRect Resources.BitmapStaticEmberSmall { x = foe.x + 25, y = y - 20, w = 16, h = 20 }
            ]


drawBubbles : Layout -> Player -> Int -> List Ui.RenderOp
drawBubbles layout player frame =
    let
        baseX =
            player.x + 56

        baseY =
            player.y
    in
    (if frame >= 1 then
        smallBubbleCluster baseX (baseY - 10)

     else
        []
    )
        ++ (if frame >= 2 then
                largeBubbleCluster (baseX + 40) (baseY - 20)

            else
                []
           )


smallBubbleCluster : Int -> Int -> List Ui.RenderOp
smallBubbleCluster x y =
    [ Ui.circle { x = x - 8, y = y - 12 } 5 Color.white
    , Ui.circle { x = x + 8, y = y - 10 } 5 Color.white
    , Ui.circle { x = x - 8, y = y + 12 } 5 Color.white
    , Ui.circle { x = x + 14, y = y + 4 } 5 Color.white
    , Ui.circle { x = x - 20, y = y } 11 Color.white
    , Ui.circle { x = x, y = y } 11 Color.white
    ]


largeBubbleCluster : Int -> Int -> List Ui.RenderOp
largeBubbleCluster x y =
    [ Ui.circle { x = x - 5, y = y - 15 } 5 Color.white
    , Ui.circle { x = x + 16, y = y + 13 } 5 Color.white
    , Ui.circle { x = x - 3, y = y + 12 } 5 Color.white
    , Ui.circle { x = x + 14, y = y - 4 } 11 Color.white
    , Ui.circle { x = x + 30, y = y - 8 } 11 Color.white
    ]


eraseBelowOpponent : Layout -> Opponent -> List Ui.RenderOp
eraseBelowOpponent layout foe =
    [ Ui.fillRect { x = foe.x, y = foe.y + 58, w = 70, h = 80 } Color.white ]


dialog : Layout -> List String -> List Ui.RenderOp
dialog layout lines =
    case lines of
        first :: second :: _ ->
            [ textCentered layout.screenW (layout.boxY + 12) (layout.screenW - 16) 14 first
            , textCentered layout.screenW (layout.boxY + 25) (layout.screenW - 16) 14 second
            ]

        [ only ] ->
            [ textCentered layout.screenW (layout.boxY + 18) (layout.screenW - 16) 14 only ]

        [] ->
            []


textCentered : Int -> Int -> Int -> Int -> String -> Ui.RenderOp
textCentered screenW y w h value =
    Ui.group
        (Ui.context [ Ui.textColor Color.white ]
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = screenW // 2 - w // 2, y = y, w = w, h = h } value ]
        )


textLeft : Int -> Int -> Int -> Int -> String -> Ui.RenderOp
textLeft x y w h value =
    Ui.group
        (Ui.context [ Ui.textColor Color.white ]
            [ Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = x, y = y, w = w, h = h } value ]
        )


square : Int -> Int -> Int -> Ui.Rect
square cx cy radius =
    { x = cx - radius, y = cy - radius, w = radius * 2, h = radius * 2 }


pad2 : Int -> String
pad2 value =
    if value < 10 then
        "0" ++ String.fromInt value

    else
        String.fromInt value
