module HeroPhysics exposing (Model, Msg, init, subscriptions, update, view)

{-| Tiny playground: green Elm “ideas” bounce around a Pebble watch.
Uses elm-physics for the simulation and Svg for rendering (no WebGL).
-}

import Block3d exposing (Block3d)
import Cylinder3d exposing (Cylinder3d)
import Direction3d
import Duration
import Frame3d exposing (Frame3d)
import Html exposing (Html, div, p, text)
import Html.Attributes exposing (attribute)
import Length exposing (Meters)
import Physics exposing (Body, Contacts)
import Physics.Material as Material
import Physics.Shape as Shape
import Plane3d
import Point3d exposing (Point3d)
import Sphere3d exposing (Sphere3d)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark)
import Tailwind.Theme exposing (gray, s3, s300, s4, s600, s700, slate)
import Time


type Id
    = Floor
    | Wall Int
    | Watch
    | ElmBall Int


type alias Model =
    { bodies : List ( Id, Body )
    , contacts : Contacts Id
    , accumulator : Float
    , elapsed : Float
    , lastMillis : Maybe Int
    }


type Msg
    = Tick Time.Posix


init : Model
init =
    { bodies = initialBodies
    , contacts = Physics.emptyContacts
    , accumulator = 0
    , elapsed = 0
    , lastMillis = Nothing
    }


{-| Prefer `Time.every` over `onAnimationFrame` so elm-pages Shared
subscriptions keep ticking even when the tab's rAF pacing is awkward.
-}
subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 32 Tick


update : Msg -> Model -> Model
update msg model =
    case msg of
        Tick now ->
            let
                nowMs =
                    Time.posixToMillis now

                dt =
                    case model.lastMillis of
                        Nothing ->
                            1 / 30

                        Just prev ->
                            min 0.064 (toFloat (max 0 (nowMs - prev)) / 1000)

                elapsed =
                    model.elapsed + dt

                base =
                    if elapsed > 8 then
                        { bodies = initialBodies
                        , contacts = Physics.emptyContacts
                        , accumulator = 0
                        , elapsed = 0
                        , lastMillis = Just nowMs
                        }

                    else
                        { model | elapsed = elapsed, lastMillis = Just nowMs }

                ( bodies, contacts, leftover ) =
                    stepFixed (base.accumulator + dt) base.bodies base.contacts
            in
            { base
                | bodies = bodies
                , contacts = contacts
                , accumulator = leftover
            }


stepFixed :
    Float
    -> List ( Id, Body )
    -> Contacts Id
    -> ( List ( Id, Body ), Contacts Id, Float )
stepFixed accumulator bodies contacts =
    let
        stepSeconds =
            Duration.inSeconds (Duration.seconds (1 / 30))

        -- Cap catch-up so a slow frame cannot freeze the UI.
        maxSteps =
            2
    in
    stepFixedHelp maxSteps accumulator bodies contacts stepSeconds


stepFixedHelp :
    Int
    -> Float
    -> List ( Id, Body )
    -> Contacts Id
    -> Float
    -> ( List ( Id, Body ), Contacts Id, Float )
stepFixedHelp stepsLeft accumulator bodies contacts stepSeconds =
    if stepsLeft <= 0 || accumulator < stepSeconds then
        ( bodies, contacts, min accumulator (stepSeconds * 2) )

    else
        let
            config =
                { simConfig
                    | contacts = contacts
                    , collide = collide
                }

            ( nextBodies, nextContacts ) =
                Physics.simulate config bodies
        in
        stepFixedHelp (stepsLeft - 1)
            (accumulator - stepSeconds)
            nextBodies
            nextContacts
            stepSeconds


simConfig : Physics.Config Id
simConfig =
    let
        base =
            Physics.onEarth
    in
    { base
        | duration = Duration.seconds (1 / 30)
        , solverIterations = 8
    }


collide : Id -> Id -> Bool
collide a b =
    case ( a, b ) of
        ( Floor, Floor ) ->
            False

        ( Wall _, Wall _ ) ->
            False

        ( Wall _, Floor ) ->
            False

        ( Floor, Wall _ ) ->
            False

        _ ->
            True


initialBodies : List ( Id, Body )
initialBodies =
    [ ( Floor, floor )
    , ( Watch, watch )
    ]
        ++ walls
        ++ elmBalls


floor : Body
floor =
    Physics.plane Plane3d.xy Material.wood


watch : Body
watch =
    let
        caseShape : Cylinder3d Meters Physics.BodyCoordinates
        caseShape =
            Cylinder3d.centeredOn Point3d.origin
                Direction3d.z
                { radius = Length.meters 0.48
                , length = Length.meters 0.2
                }
    in
    Physics.static [ ( Shape.cylinder 16 caseShape, Material.plastic ) ]
        |> Physics.moveTo (Point3d.meters 0 0 0.12)


walls : List ( Id, Body )
walls =
    [ wall 0 (Block3d.from (Point3d.meters -2.0 -2.0 0) (Point3d.meters 2.0 -1.9 1.0))
    , wall 1 (Block3d.from (Point3d.meters -2.0 1.9 0) (Point3d.meters 2.0 2.0 1.0))
    , wall 2 (Block3d.from (Point3d.meters -2.0 -2.0 0) (Point3d.meters -1.9 2.0 1.0))
    , wall 3 (Block3d.from (Point3d.meters 1.9 -2.0 0) (Point3d.meters 2.0 2.0 1.0))
    ]


wall : Int -> Block3d Meters Physics.BodyCoordinates -> ( Id, Body )
wall index block =
    ( Wall index
    , Physics.static [ ( Shape.block block, Material.wood ) ]
    )


elmBalls : List ( Id, Body )
elmBalls =
    [ ( -1.0, 0.7, 1.8 )
    , ( 0.8, -0.6, 2.1 )
    , ( -0.3, -1.0, 2.4 )
    , ( 1.1, 0.9, 1.9 )
    ]
        |> List.indexedMap
            (\i ( x, y, z ) ->
                ( ElmBall i
                , Physics.sphere elmSphere Material.rubber
                    |> Physics.moveTo (Point3d.meters x y z)
                    |> Physics.damp { linear = 0.05, angular = 0.08 }
                )
            )


elmSphere : Sphere3d Meters Physics.BodyCoordinates
elmSphere =
    Sphere3d.atOrigin (Length.meters 0.22)



-- VIEW


view : Model -> Html msg
view model =
    div
        [ classes
            [ Tw.w_full
            , Tw.overflow_hidden
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s300)
            , Tw.bg_color (slate s700)
            , dark [ Tw.border_color (slate s600) ]
            ]
        , attribute "aria-label" "Animation of Elm-colored spheres bouncing around a Pebble watch"
        ]
        [ Svg.svg
            [ SA.viewBox "0 0 420 280"
            , SA.width "100%"
            , SA.height "100%"
            , attribute "role" "img"
            ]
            (defs
                :: floorTiles
                :: pulseRing model.elapsed
                :: (model.bodies
                        |> List.filterMap (drawable model.elapsed)
                        |> List.sortBy .depth
                        |> List.concatMap .nodes
                   )
            )
        , p
            [ classes
                [ Tw.px s4
                , Tw.py s3
                , Tw.text_sm
                , Tw.text_color (gray s300)
                ]
            ]
            [ text "Elm ideas bounce until they settle on a Pebble — physics by elm-physics, drawn in Svg." ]
        ]


type alias Drawable msg =
    { depth : Float
    , nodes : List (Svg msg)
    }


drawable : Float -> ( Id, Body ) -> Maybe (Drawable msg)
drawable elapsed ( id, body ) =
    let
        frame =
            Physics.frame body

        origin =
            Frame3d.originPoint frame

        { x, y, z } =
            Point3d.unwrap origin

        ( sx, sy ) =
            project x y z

        depth =
            x + y - z
    in
    case id of
        Floor ->
            Nothing

        Wall _ ->
            Nothing

        Watch ->
            Just
                { depth = depth
                , nodes = [ pebbleWatch sx sy z elapsed ]
                }

        ElmBall i ->
            Just
                { depth = depth
                , nodes = [ elmIdea sx sy z i ]
                }


defs : Svg msg
defs =
    Svg.defs []
        [ Svg.radialGradient
            [ SA.id "elmBall"
            , SA.cx "35%"
            , SA.cy "30%"
            , SA.r "65%"
            ]
            [ Svg.stop [ SA.offset "0%", SA.stopColor "#9BE15D" ] []
            , Svg.stop [ SA.offset "55%", SA.stopColor "#5A8F2F" ] []
            , Svg.stop [ SA.offset "100%", SA.stopColor "#3F6B22" ] []
            ]
        , Svg.radialGradient
            [ SA.id "pebbleFace"
            , SA.cx "40%"
            , SA.cy "35%"
            , SA.r "70%"
            ]
            [ Svg.stop [ SA.offset "0%", SA.stopColor "#1e293b" ] []
            , Svg.stop [ SA.offset "100%", SA.stopColor "#020617" ] []
            ]
        , Svg.filter [ SA.id "softShadow" ]
            [ Svg.node "feDropShadow"
                [ SA.dx "0"
                , SA.dy "3"
                , SA.stdDeviation "2.5"
                , SA.floodColor "#000"
                , SA.floodOpacity "0.45"
                ]
                []
            ]
        ]


floorTiles : Svg msg
floorTiles =
    let
        corners =
            [ ( -2, -2, 0 )
            , ( 2, -2, 0 )
            , ( 2, 2, 0 )
            , ( -2, 2, 0 )
            ]
                |> List.map (\( x, y, z ) -> project x y z)
                |> pointsAttr
    in
    Svg.polygon
        [ SA.points corners
        , SA.fill "#334155"
        , SA.stroke "#475569"
        , SA.strokeWidth "1"
        ]
        []


pulseRing : Float -> Svg msg
pulseRing elapsed =
    let
        ( cx, cy ) =
            project 0 0 0.12

        radius =
            52 + 10 * sin (elapsed * 3)
    in
    Svg.circle
        [ SA.cx (String.fromFloat cx)
        , SA.cy (String.fromFloat cy)
        , SA.r (String.fromFloat radius)
        , SA.fill "none"
        , SA.stroke "#5A8F2F"
        , SA.strokeWidth "2"
        , SA.opacity (String.fromFloat (0.35 + 0.25 * sin (elapsed * 3)))
        ]
        []


pebbleWatch : Float -> Float -> Float -> Float -> Svg msg
pebbleWatch sx sy z elapsed =
    let
        radius =
            38 + z * 4

        ( bandLeftX, bandLeftY ) =
            project -0.95 0 0.12

        ( bandRightX, bandRightY ) =
            project 0.95 0 0.12

        -- Hands always tick from elapsed so motion is obvious even after balls rest.
        hourAngle =
            elapsed * 0.7

        minuteAngle =
            elapsed * 2.4

        hourLen =
            radius * 0.36

        minuteLen =
            radius * 0.52

        hx =
            sx + hourLen * cos hourAngle

        hy =
            sy + hourLen * sin hourAngle

        mx =
            sx + minuteLen * cos minuteAngle

        my =
            sy + minuteLen * sin minuteAngle
    in
    Svg.g [ SA.filter "url(#softShadow)" ]
        [ Svg.line
            [ SA.x1 (String.fromFloat bandLeftX)
            , SA.y1 (String.fromFloat bandLeftY)
            , SA.x2 (String.fromFloat sx)
            , SA.y2 (String.fromFloat sy)
            , SA.stroke "#0f172a"
            , SA.strokeWidth "14"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.line
            [ SA.x1 (String.fromFloat sx)
            , SA.y1 (String.fromFloat sy)
            , SA.x2 (String.fromFloat bandRightX)
            , SA.y2 (String.fromFloat bandRightY)
            , SA.stroke "#0f172a"
            , SA.strokeWidth "14"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.circle
            [ SA.cx (String.fromFloat sx)
            , SA.cy (String.fromFloat sy)
            , SA.r (String.fromFloat radius)
            , SA.fill "#94a3b8"
            , SA.stroke "#e2e8f0"
            , SA.strokeWidth "2"
            ]
            []
        , Svg.circle
            [ SA.cx (String.fromFloat sx)
            , SA.cy (String.fromFloat sy)
            , SA.r (String.fromFloat (radius * 0.78))
            , SA.fill "url(#pebbleFace)"
            ]
            []
        , Svg.text_
            [ SA.x (String.fromFloat sx)
            , SA.y (String.fromFloat (sy - radius * 0.28))
            , SA.textAnchor "middle"
            , SA.fill "#5A8F2F"
            , SA.fontSize "11"
            , SA.fontFamily "ui-monospace, SFMono-Regular, Menlo, monospace"
            , SA.fontWeight "700"
            ]
            [ Svg.text "elm" ]
        , Svg.line
            [ SA.x1 (String.fromFloat sx)
            , SA.y1 (String.fromFloat sy)
            , SA.x2 (String.fromFloat hx)
            , SA.y2 (String.fromFloat hy)
            , SA.stroke "#f8fafc"
            , SA.strokeWidth "2.5"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.line
            [ SA.x1 (String.fromFloat sx)
            , SA.y1 (String.fromFloat sy)
            , SA.x2 (String.fromFloat mx)
            , SA.y2 (String.fromFloat my)
            , SA.stroke "#a3e635"
            , SA.strokeWidth "1.5"
            , SA.strokeLinecap "round"
            ]
            []
        , Svg.circle
            [ SA.cx (String.fromFloat sx)
            , SA.cy (String.fromFloat sy)
            , SA.r "3"
            , SA.fill "#f8fafc"
            ]
            []
        , Svg.rect
            [ SA.x (String.fromFloat (sx + radius - 2))
            , SA.y (String.fromFloat (sy - 5))
            , SA.width "7"
            , SA.height "10"
            , SA.rx "2"
            , SA.fill "#cbd5e1"
            ]
            []
        ]


elmIdea : Float -> Float -> Float -> Int -> Svg msg
elmIdea sx sy z index =
    let
        radius =
            16 + z * 3

        label =
            case modBy 3 index of
                0 ->
                    "elm"

                1 ->
                    "λ"

                _ ->
                    "Msg"
    in
    Svg.g [ SA.filter "url(#softShadow)" ]
        [ Svg.circle
            [ SA.cx (String.fromFloat (sx + 3))
            , SA.cy (String.fromFloat (sy + 5))
            , SA.r (String.fromFloat (radius * 0.9))
            , SA.fill "#0f172a"
            , SA.opacity "0.25"
            ]
            []
        , Svg.circle
            [ SA.cx (String.fromFloat sx)
            , SA.cy (String.fromFloat sy)
            , SA.r (String.fromFloat radius)
            , SA.fill "url(#elmBall)"
            , SA.stroke "#d9f99d"
            , SA.strokeWidth "1.5"
            ]
            []
        , Svg.text_
            [ SA.x (String.fromFloat sx)
            , SA.y (String.fromFloat (sy + 4))
            , SA.textAnchor "middle"
            , SA.fill "#f7fee7"
            , SA.fontSize "11"
            , SA.fontFamily "ui-monospace, SFMono-Regular, Menlo, monospace"
            , SA.fontWeight "700"
            ]
            [ Svg.text label ]
        ]


project : Float -> Float -> Float -> ( Float, Float )
project x y z =
    let
        scale =
            58

        sx =
            210 + (x - y) * scale * 0.866

        sy =
            168 - z * scale + (x + y) * scale * 0.5
    in
    ( sx, sy )


pointsAttr : List ( Float, Float ) -> String
pointsAttr pts =
    pts
        |> List.map (\( x, y ) -> String.fromFloat x ++ "," ++ String.fromFloat y)
        |> String.join " "
