module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Frame as Frame
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { screenW : Int
    , screenH : Int
    , pageIndex : Int
    , rotationAngle : Int
    }


type Page
    = Primitives
    | Paths
    | TextPage
    | StaticBitmap
    | AnimatedBitmap
    | StaticVector
    | AnimatedVector
    | Combined


type Msg
    = UpPressed
    | DownPressed
    | FrameTick Frame.Frame


pages : List Page
pages =
    [ Primitives
    , Paths
    , TextPage
    , StaticBitmap
    , AnimatedBitmap
    , StaticVector
    , AnimatedVector
    , Combined
    ]


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { screenW = context.screen.width
      , screenH = context.screen.height
      , pageIndex = 0
      , rotationAngle = 0
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpPressed ->
            ( { model | pageIndex = prevIndex model.pageIndex }, Cmd.none )

        DownPressed ->
            ( { model | pageIndex = nextIndex model.pageIndex }, Cmd.none )

        FrameTick _ ->
            ( { model | rotationAngle = modBy 65536 (model.rotationAngle + 4096) }, Cmd.none )


prevIndex : Int -> Int
prevIndex index =
    let
        count =
            List.length pages
    in
    modBy count (index - 1 + count)


nextIndex : Int -> Int
nextIndex index =
    modBy (List.length pages) (index + 1)


currentPage : Int -> Page
currentPage index =
    pages
        |> List.drop (modBy (List.length pages) index)
        |> List.head
        |> Maybe.withDefault Primitives


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        , Frame.every 33 FrameTick
        ]


view : Model -> Ui.UiNode
view model =
    let
        page =
            currentPage model.pageIndex

        header =
            headerOps model page
    in
    header
        ++ pageOps model page
        |> Ui.toUiNode


headerOps : Model -> Page -> List Ui.RenderOp
headerOps model page =
    [ Ui.clear Color.white
    , Ui.text Resources.DefaultFont Ui.defaultTextOptions
        { x = 0, y = 2, w = model.screenW, h = 18 }
        (pageTitle page ++ " " ++ String.fromInt (model.pageIndex + 1) ++ "/" ++ String.fromInt (List.length pages))
        , Ui.text Resources.DefaultFont
        (Ui.alignLeft Ui.defaultTextOptions |> Ui.trailingEllipsis)
        { x = 4, y = model.screenH - 16, w = model.screenW - 8, h = 14 }
        "Up/Down: page"
    ]


pageTitle : Page -> String
pageTitle page =
    case page of
        Primitives ->
            "Primitives"

        Paths ->
            "Paths"

        TextPage ->
            "Text"

        StaticBitmap ->
            "Bitmap"

        AnimatedBitmap ->
            "Anim BMP"

        StaticVector ->
            "Vector"

        AnimatedVector ->
            "Anim Vec"

        Combined ->
            "Combined"


pageOps : Model -> Page -> List Ui.RenderOp
pageOps model page =
    case page of
        Primitives ->
            primitivesOps model

        Paths ->
            pathsOps

        TextPage ->
            textOps model

        StaticBitmap ->
            staticBitmapOps model

        AnimatedBitmap ->
            animatedBitmapOps model

        StaticVector ->
            staticVectorOps model

        AnimatedVector ->
            animatedVectorOps model

        Combined ->
            combinedOps model


contentTop : Int
contentTop =
    22


primitivesOps : Model -> List Ui.RenderOp
primitivesOps model =
    let
        w =
            model.screenW

        h =
            model.screenH - contentTop - 18
    in
    [ Ui.fillRect { x = 0, y = contentTop, w = w, h = h } Color.lightGray
    , Ui.rect { x = 4, y = contentTop + 4, w = 40, h = 24 } Color.black
    , Ui.fillRect { x = 50, y = contentTop + 4, w = 36, h = 24 } Color.cobaltBlue
    , Ui.line { x = 92, y = contentTop + 4 } { x = 132, y = contentTop + 28 } Color.red
    , Ui.circle { x = 24, y = contentTop + 52 } 10 Color.black
    , Ui.fillCircle { x = 72, y = contentTop + 52 } 12 Color.green
    , Ui.pixel { x = 120, y = contentTop + 52 } Color.red
    , Ui.roundRect { x = 4, y = contentTop + 72, w = 56, h = 28 } 6 Color.black
    , Ui.arc { x = 68, y = contentTop + 72, w = 36, h = 28 } 0 32768
    , Ui.fillRadial { x = 108, y = contentTop + 72, w = 32, h = 28 } 0 49152
    ]


pathsOps : List Ui.RenderOp
pathsOps =
    let
        y0 =
            contentTop + 8

        triangle =
            Ui.path
                [ { x = 20, y = y0 + 40 }
                , { x = 60, y = y0 + 40 }
                , { x = 40, y = y0 }
                ]
                { x = 0, y = 0 }
                (Ui.rotationFromDegrees 0)
    in
    [ Ui.group
        (Ui.context
            [ Ui.strokeWidth 2
            , Ui.strokeColor Color.black
            , Ui.fillColor Color.chromeYellow
            , Ui.antialiased 1
            ]
            [ Ui.pathFilled triangle
            , Ui.pathOutline triangle
            , Ui.pathOutlineOpen
                (Ui.path
                    [ { x = 80, y = y0 + 10 }
                    , { x = 120, y = y0 + 10 }
                    , { x = 100, y = y0 + 44 }
                    ]
                    { x = 0, y = 0 }
                    (Ui.rotationFromDegrees 0)
                )
            ]
        )
    ]


textOps : Model -> List Ui.RenderOp
textOps model =
    let
    y0 =
        contentTop + 4
  in
  [ Ui.text Resources.DefaultFont Ui.defaultTextOptions
      { x = 0, y = y0, w = model.screenW, h = 20 }
      "Centered text"
  , Ui.text Resources.DefaultFont
      (Ui.alignLeft Ui.defaultTextOptions)
      { x = 4, y = y0 + 24, w = model.screenW - 8, h = 20 }
      "Left aligned"
  , Ui.text Resources.DefaultFont
      (Ui.alignRight Ui.defaultTextOptions)
      { x = 4, y = y0 + 48, w = model.screenW - 8, h = 20 }
      "Right aligned"
  , Ui.textInt Resources.DefaultFont { x = 4, y = y0 + 72 } 42
  , Ui.textLabel Resources.DefaultFont { x = 4, y = y0 + 96 } Ui.WaitingForCompanion
  ]


staticBitmapOps : Model -> List Ui.RenderOp
staticBitmapOps model =
    let
        cx =
            model.screenW // 2

        cy =
            (model.screenH + contentTop) // 2
    in
    [ Ui.drawBitmapInRect Resources.BitmapStaticBtIcon
        { x = 8, y = contentTop + 8, w = 30, h = 30 }
    , Ui.drawRotatedBitmap Resources.BitmapStaticBtIcon
        { x = 0, y = 0, w = 30, h = 30 }
        (Ui.rotationFromPebbleAngle model.rotationAngle)
        { x = cx, y = cy }
    ]


animatedBitmapOps : Model -> List Ui.RenderOp
animatedBitmapOps model =
    let
        cx =
            model.screenW // 2 - 8

        cy =
            (model.screenH + contentTop) // 2 - 8
    in
    [ Ui.drawBitmapSequenceAt Resources.BitmapAnimatedSparkle { x = cx, y = cy } ]


staticVectorOps : Model -> List Ui.RenderOp
staticVectorOps model =
    let
        origin =
            iconOrigin model 40
    in
    [ Ui.drawVectorAt Resources.VectorStaticWeatherClear origin ]


animatedVectorOps : Model -> List Ui.RenderOp
animatedVectorOps model =
    let
        origin =
            iconOrigin model 40
    in
    [ Ui.drawVectorSequenceAt Resources.VectorAnimatedTransitionClearToCloudy origin ]


combinedOps : Model -> List Ui.RenderOp
combinedOps model =
    let
        y0 =
            contentTop + 4
    in
    [ Ui.fillRect { x = 4, y = y0, w = 40, h = 20 } Color.cobaltBlue
    , Ui.text Resources.DefaultFont
        (Ui.alignLeft Ui.defaultTextOptions |> Ui.trailingEllipsis)
        { x = 48, y = y0, w = 88, h = 20 }
        "All kinds"
    , Ui.drawBitmapInRect Resources.BitmapStaticBtIcon { x = 4, y = y0 + 28, w = 20, h = 20 }
    , Ui.drawBitmapSequenceAt Resources.BitmapAnimatedSparkle { x = 30, y = y0 + 28 }
    , Ui.drawVectorAt Resources.VectorStaticWeatherClear { x = 56, y = y0 + 24 }
    , Ui.drawVectorSequenceAt Resources.VectorAnimatedTransitionClearToCloudy { x = 96, y = y0 + 24 }
    , Ui.line { x = 4, y = y0 + 56 } { x = model.screenW - 4, y = y0 + 56 } Color.black
    , Ui.fillCircle { x = model.screenW // 2, y = y0 + 80 } 14 Color.green
    ]


iconOrigin : Model -> Int -> Ui.Point
iconOrigin model size =
    { x = model.screenW // 2 - size // 2
    , y = (model.screenH + contentTop) // 2 - size // 2
    }


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
