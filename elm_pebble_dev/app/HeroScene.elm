module HeroScene exposing (Model, Msg, init, subscriptions, update, view)

{-| Pebble watchface featuring the Elm tangram (heart) logo, rendered with
elm-3d-scene (WebGL under the hood).

Keeps CPU light: no physics solver — just a slow camera orbit and a few
procedural entity transforms at ~16 Hz (`Time.every 64`).
-}

import Angle exposing (Angle)
import Block3d
import Browser.Events
import Camera3d
import Color exposing (Color)
import Cylinder3d
import Direction3d
import Duration exposing (Duration)
import Frame3d
import Html exposing (Html, div, p, text)
import Html.Attributes exposing (attribute, style)
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Length exposing (Meters)
import Pixels exposing (Pixels)
import Point3d exposing (Point3d)
import Quantity exposing (Quantity)
import Scene3d
import Scene3d.Material as Material
import Sphere3d
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark)
import Tailwind.Theme exposing (gray, s3, s300, s4, s600, s700, slate)
import Time
import Triangle3d


type WorldCoordinates
    = WorldCoordinates


type alias Model =
    { azimuth : Angle
    , elevation : Angle
    , elapsed : Duration
    , orbiting : Bool
    }


type Msg
    = Tick Time.Posix
    | MouseDown
    | MouseUp
    | MouseMove (Quantity Float Pixels) (Quantity Float Pixels)


{-| One tick every 64 ms (~15.6 Hz). Plenty for slow orbits; much cheaper than
`onAnimationFrame` + a physics step.
-}
tickMs : Float
tickMs =
    64


{-| Official Elm logo palette (tangram / “heart”).
-}
elmCyan : Color
elmCyan =
    Color.rgb255 96 181 204


elmGreen : Color
elmGreen =
    Color.rgb255 127 209 59


elmGrey : Color
elmGrey =
    Color.rgb255 90 99 120


elmOrange : Color
elmOrange =
    Color.rgb255 240 173 0


init : Model
init =
    { azimuth = Angle.degrees 42
    , elevation = Angle.degrees 28
    , elapsed = Duration.seconds 0
    , orbiting = False
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every tickMs Tick
        , if model.orbiting then
            Sub.batch
                [ Browser.Events.onMouseMove decodeMouseMove
                , Browser.Events.onMouseUp (Decode.succeed MouseUp)
                ]

          else
            Sub.none
        ]


decodeMouseMove : Decoder Msg
decodeMouseMove =
    Decode.map2 MouseMove
        (Decode.field "movementX" (Decode.map Pixels.float Decode.float))
        (Decode.field "movementY" (Decode.map Pixels.float Decode.float))


update : Msg -> Model -> Model
update msg model =
    case msg of
        Tick _ ->
            let
                step =
                    Duration.milliseconds tickMs

                autoOrbit =
                    Angle.degrees 10
                        |> Quantity.per Duration.second
                        |> Quantity.for step
            in
            { model
                | elapsed = Quantity.plus model.elapsed step
                , azimuth =
                    if model.orbiting then
                        model.azimuth

                    else
                        Quantity.plus model.azimuth autoOrbit
            }

        MouseDown ->
            { model | orbiting = True }

        MouseUp ->
            { model | orbiting = False }

        MouseMove dx dy ->
            if model.orbiting then
                let
                    rate =
                        Angle.degrees 0.35 |> Quantity.per Pixels.pixel
                in
                { model
                    | azimuth = model.azimuth |> Quantity.minus (dx |> Quantity.at rate)
                    , elevation =
                        model.elevation
                            |> Quantity.plus (dy |> Quantity.at rate)
                            |> Quantity.clamp (Angle.degrees 8) (Angle.degrees 70)
                }

            else
                model


view : Model -> Html Msg
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
        , attribute "aria-label" "3D WebGL scene of a Pebble watch with the Elm tangram logo on the face"
        , Html.Events.onMouseDown MouseDown
        , style "touch-action" "none"
        , style "cursor"
            (if model.orbiting then
                "grabbing"

             else
                "grab"
            )
        ]
        [ scene model
        , p
            [ classes
                [ Tw.px s4
                , Tw.py s3
                , Tw.text_sm
                , Tw.text_color (gray s300)
                ]
            ]
            [ text "Drag to orbit. Watch face is the Elm tangram (heart) — ianmackenzie/elm-3d-scene over elm-explorations/webgl." ]
        ]


scene : Model -> Html msg
scene model =
    let
        t =
            Duration.inSeconds model.elapsed

        camera =
            Camera3d.orbitZ
                { focalPoint = Point3d.meters 0 0 0.18
                , azimuth = model.azimuth
                , elevation = model.elevation
                , distance = Length.meters 2.45
                , fov = Camera3d.angle (Angle.degrees 32)
                , projection = Camera3d.Perspective
                }
    in
    Scene3d.sunny
        { upDirection = Direction3d.z
        , sunlightDirection = Direction3d.xyZ (Angle.degrees -35) (Angle.degrees -55)
        , shadows = False
        , camera = camera
        , clipDepth = Length.meters 0.1
        , dimensions = ( Pixels.int 720, Pixels.int 400 )
        , background = Scene3d.backgroundColor (Color.rgb255 15 23 42)
        , entities =
            [ floor
            , pebbleWatch t
            , Scene3d.group (orbitRing t)
            , Scene3d.group (elmIdeas t)
            ]
        }


floor : Scene3d.Entity WorldCoordinates
floor =
    -- Matte floor is cheaper to shade than metal/nonmetal PBR.
    Scene3d.cylinder (Material.matte (Color.rgb255 51 65 85)) <|
        Cylinder3d.centeredOn (Point3d.meters 0 0 -0.02)
            Direction3d.z
            { radius = Length.meters 1.55
            , length = Length.meters 0.04
            }


pebbleWatch : Float -> Scene3d.Entity WorldCoordinates
pebbleWatch t =
    let
        caseMaterial =
            Material.metal { baseColor = Color.rgb255 148 163 184, roughness = 0.28 }

        bezelMaterial =
            Material.metal { baseColor = Color.rgb255 100 116 139, roughness = 0.22 }

        faceMaterial =
            Material.nonmetal { baseColor = Color.rgb255 15 23 42, roughness = 0.55 }

        bandMaterial =
            Material.nonmetal { baseColor = Color.rgb255 30 41 59, roughness = 0.7 }

        bob =
            Length.meters (0.015 * sin (t * 1.4))

        body =
            Scene3d.cylinder caseMaterial <|
                Cylinder3d.centeredOn (Point3d.meters 0 0 0.12)
                    Direction3d.z
                    { radius = Length.meters 0.42
                    , length = Length.meters 0.16
                    }

        bezel =
            Scene3d.cylinder bezelMaterial <|
                Cylinder3d.centeredOn (Point3d.meters 0 0 0.205)
                    Direction3d.z
                    { radius = Length.meters 0.38
                    , length = Length.meters 0.03
                    }

        face =
            Scene3d.cylinder faceMaterial <|
                Cylinder3d.centeredOn (Point3d.meters 0 0 0.22)
                    Direction3d.z
                    { radius = Length.meters 0.33
                    , length = Length.meters 0.015
                    }

        bandLeft =
            Scene3d.block bandMaterial <|
                Block3d.centeredOn
                    (Frame3d.atPoint (Point3d.meters -0.62 0 0.12))
                    ( Length.meters 0.55, Length.meters 0.22, Length.meters 0.06 )

        bandRight =
            Scene3d.block bandMaterial <|
                Block3d.centeredOn
                    (Frame3d.atPoint (Point3d.meters 0.62 0 0.12))
                    ( Length.meters 0.55, Length.meters 0.22, Length.meters 0.06 )

        crown =
            Scene3d.cylinder caseMaterial <|
                Cylinder3d.centeredOn (Point3d.meters 0.46 0 0.12)
                    Direction3d.x
                    { radius = Length.meters 0.035
                    , length = Length.meters 0.08
                    }
    in
    Scene3d.group
        [ bandLeft
        , bandRight
        , body
        , bezel
        , face
        , crown
        , elmTangramFace
        ]
        |> Scene3d.translateIn Direction3d.z bob


{-| Flat Elm tangram on the watch face.

Polygon coordinates match `Utils.Logo` from package.elm-lang.org (viewBox 0–600),
colored like the official multi-color logo.
-}
elmTangramFace : Scene3d.Entity WorldCoordinates
elmTangramFace =
    Scene3d.group
        [ -- Left grey triangle
          logoTri elmGrey ( 0, 20 ) ( 280, 300 ) ( 0, 580 )
        , -- Bottom cyan triangle
          logoTri elmCyan ( 20, 600 ) ( 300, 320 ) ( 580, 600 )
        , -- Top-right cyan triangle
          logoTri elmCyan ( 320, 0 ) ( 600, 0 ) ( 600, 280 )
        , -- Top green parallelogram (two tris)
          logoTri elmGreen ( 20, 0 ) ( 280, 0 ) ( 402, 122 )
        , logoTri elmGreen ( 20, 0 ) ( 402, 122 ) ( 142, 122 )
        , -- Center orange triangle
          logoTri elmOrange ( 170, 150 ) ( 430, 150 ) ( 300, 280 )
        , -- Green diamond (two tris)
          logoTri elmGreen ( 320, 300 ) ( 450, 170 ) ( 580, 300 )
        , logoTri elmGreen ( 320, 300 ) ( 580, 300 ) ( 450, 430 )
        , -- Bottom-right orange triangle
          logoTri elmOrange ( 470, 450 ) ( 600, 320 ) ( 600, 580 )
        ]


logoTri :
    Color
    -> ( Float, Float )
    -> ( Float, Float )
    -> ( Float, Float )
    -> Scene3d.Entity WorldCoordinates
logoTri color a b c =
    Scene3d.triangle (Material.color color)
        (Triangle3d.from (logoPoint a) (logoPoint b) (logoPoint c))


{-| Map logo SVG units into meters on the watch face (Z just above the dial).
-}
logoPoint : ( Float, Float ) -> Point3d Meters WorldCoordinates
logoPoint ( x, y ) =
    let
        -- Fit the 600×600 logo inside the ~0.66 m face diameter with a small margin.
        scale =
            0.00092

        cx =
            300

        cy =
            300
    in
    Point3d.meters
        ((x - cx) * scale)
        ((cy - y) * scale)
        0.232


type alias Idea =
    { index : Int
    , radius : Float
    , speed : Float
    , bob : Float
    , size : Float
    , color : Color
    }


elmIdeas : Float -> List (Scene3d.Entity WorldCoordinates)
elmIdeas t =
    [ { index = 0, radius = 0.85, speed = 0.55, bob = 0.9, size = 0.13, color = elmGreen }
    , { index = 1, radius = 1.05, speed = 1.05, bob = 1.2, size = 0.11, color = elmCyan }
    , { index = 2, radius = 0.72, speed = 1.55, bob = 0.75, size = 0.09, color = elmOrange }
    , { index = 3, radius = 1.2, speed = 0.4, bob = 1.35, size = 0.15, color = elmGreen }
    , { index = 4, radius = 0.95, speed = -0.7, bob = 1.0, size = 0.08, color = elmGrey }
    ]
        |> List.map
            (\idea ->
                let
                    phase =
                        toFloat idea.index * 1.25

                    x =
                        idea.radius * cos (t * idea.speed + phase)

                    y =
                        idea.radius * sin (t * idea.speed + phase)

                    z =
                        0.42 + 0.16 * sin (t * idea.bob + phase)
                in
                Scene3d.sphere
                    (Material.nonmetal { baseColor = idea.color, roughness = 0.32 })
                    (Sphere3d.atPoint (Point3d.meters x y z) (Length.meters idea.size))
            )


{-| Sparse marker spheres along a shared orbit — reads as a ring without a dense mesh.
-}
orbitRing : Float -> List (Scene3d.Entity WorldCoordinates)
orbitRing t =
    let
        spin =
            t * 0.35
    in
    List.range 0 17
        |> List.map
            (\i ->
                let
                    a =
                        spin + toFloat i * (pi * 2 / 18)

                    x =
                        1.0 * cos a

                    y =
                        1.0 * sin a
                in
                Scene3d.sphere (Material.matte (Color.rgb255 71 85 105))
                    (Sphere3d.atPoint (Point3d.meters x y 0.08) (Length.meters 0.025))
            )
