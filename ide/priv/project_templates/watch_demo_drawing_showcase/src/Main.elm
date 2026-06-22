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
    , displayShape : Platform.DisplayShape
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
      , displayShape = context.screen.shape
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
subscriptions model =
    let
        frameSub =
            if currentPage model.pageIndex == StaticBitmap then
                Frame.every 33 FrameTick

            else
                Sub.none
    in
    Events.batch
        [ Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        , frameSub
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
    let
        title =
            pageTitle page
                ++ " "
                ++ String.fromInt (model.pageIndex + 1)
                ++ "/"
                ++ String.fromInt (List.length pages)

        textOptions =
            if Platform.displayShapeIsRound model.displayShape then
                Ui.alignCenter Ui.defaultTextOptions

            else
                Ui.defaultTextOptions
    in
    if Platform.displayShapeIsRound model.displayShape then
        let
            diameter =
                min model.screenW model.screenH

            inset =
                diameter // 12

            textW =
                (diameter * 4) // 9

            textX =
                (model.screenW - textW) // 2

            titleY =
                inset

            hintY =
                model.screenH - chromeBottom model - 16
        in
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOptions
            { x = textX, y = titleY, w = textW, h = 16 }
            title
        , Ui.text Resources.DefaultFont
            (Ui.alignLeft textOptions |> Ui.trailingEllipsis)
            { x = textX, y = hintY, w = textW, h = 16 }
            "Up/Down: page"
        ]

    else
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOptions
            { x = 4, y = 4, w = model.screenW - 8, h = 16 }
            title
        , Ui.text Resources.DefaultFont
            (Ui.alignLeft Ui.defaultTextOptions |> Ui.trailingEllipsis)
            { x = 4, y = model.screenH - 18, w = model.screenW - 8, h = 14 }
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
            pathsOps model

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


contentTop : Model -> Int
contentTop model =
    if Platform.displayShapeIsRound model.displayShape then
        26

    else
        22


chromeBottom : Model -> Int
chromeBottom model =
    if Platform.displayShapeIsRound model.displayShape then
        24

    else
        18


primitivesOps : Model -> List Ui.RenderOp
primitivesOps model =
    let
        w =
            model.screenW

        top =
            contentTop model

        h =
            model.screenH - top - chromeBottom model
    in
    [ Ui.fillRect { x = 0, y = top, w = w, h = h } Color.lightGray
    , Ui.rect { x = 4, y = top + 4, w = 40, h = 24 } Color.black
    , Ui.fillRect { x = 50, y = top + 4, w = 36, h = 24 } Color.cobaltBlue
    , Ui.line { x = 92, y = top + 4 } { x = 132, y = top + 28 } Color.red
    , Ui.circle { x = 24, y = top + 52 } 10 Color.black
    , Ui.fillCircle { x = 72, y = top + 52 } 12 Color.green
    , Ui.pixel { x = 120, y = top + 52 } Color.red
    , Ui.roundRect { x = 4, y = top + 72, w = 56, h = 28 } 6 Color.black
    , Ui.arc { x = 68, y = top + 72, w = 36, h = 28 } 0 32768
    , Ui.fillRadial { x = 108, y = top + 72, w = 32, h = 28 } 0 49152
    ]


pathsOps : Model -> List Ui.RenderOp
pathsOps model =
    let
        y0 =
            contentTop model + 8

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
            contentTop model + 4
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
            (model.screenH + contentTop model) // 2
    in
    [ Ui.drawBitmapInRect Resources.BitmapStaticBtIcon
        { x = 8, y = contentTop model + 8, w = 30, h = 30 }
    , Ui.drawRotatedBitmap Resources.BitmapStaticBtIcon
        { x = 0, y = 0, w = 30, h = 30 }
        (Ui.rotationFromPebbleAngle model.rotationAngle)
        { x = cx, y = cy }
    ]


animatedBitmapOps : Model -> List Ui.RenderOp
animatedBitmapOps model =
    let
        spriteSize =
            60

        cx =
            model.screenW // 2 - spriteSize // 2

        cy =
            (model.screenH + contentTop model) // 2 - spriteSize // 2
    in
    [ Ui.drawBitmapSequenceAt Resources.BitmapAnimatedSparkle { x = cx, y = cy } ]


staticVectorOps : Model -> List Ui.RenderOp
staticVectorOps model =
    let
        origin =
            iconOrigin model 40
    in
    [ Ui.drawVectorAt Resources.VectorStaticWeatherClear origin ]


animatedVectorAnimId : Ui.AnimationId
animatedVectorAnimId =
    Ui.AnimationId 1


combinedVectorAnimId : Ui.AnimationId
combinedVectorAnimId =
    Ui.AnimationId 2


animatedVectorOps : Model -> List Ui.RenderOp
animatedVectorOps model =
    let
        origin =
            iconOrigin model 40
    in
    [ Ui.drawVectorSequenceAt animatedVectorAnimId Resources.VectorAnimatedTransitionClearToCloudy origin ]


combinedOps : Model -> List Ui.RenderOp
combinedOps model =
    let
        y0 =
            contentTop model + 4

        spriteSize =
            60

        spriteY =
            y0 + 36
    in
    [ Ui.fillRect { x = 4, y = y0, w = 40, h = 20 } Color.cobaltBlue
    , Ui.text Resources.DefaultFont
        (Ui.alignLeft Ui.defaultTextOptions |> Ui.trailingEllipsis)
        { x = 48, y = y0, w = 88, h = 20 }
        "All kinds"
    , Ui.drawBitmapInRect Resources.BitmapStaticBtIcon { x = 4, y = y0 + 28, w = 20, h = 20 }
    , Ui.drawVectorAt Resources.VectorStaticWeatherClear { x = 32, y = y0 + 24 }
    , Ui.drawVectorSequenceAt combinedVectorAnimId Resources.VectorAnimatedTransitionClearToCloudy { x = 72, y = y0 + 24 }
    , Ui.drawBitmapSequenceAt Resources.BitmapAnimatedSparkle
        { x = model.screenW // 2 - spriteSize // 2, y = spriteY }
    , Ui.line { x = 4, y = spriteY + spriteSize + 4 }
        { x = model.screenW - 4, y = spriteY + spriteSize + 4 }
        Color.black
    , Ui.fillCircle { x = model.screenW // 2, y = spriteY + spriteSize + 20 } 10 Color.green
    ]


iconOrigin : Model -> Int -> Ui.Point
iconOrigin model size =
    { x = model.screenW // 2 - size // 2
    , y = (model.screenH + contentTop model) // 2 - size // 2
    }


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
