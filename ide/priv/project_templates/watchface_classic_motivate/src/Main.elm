module Main exposing (main)

import Companion.Types exposing (PhoneToWatch(..), ThemeColor(..), WatchToPhone(..))
import Companion.Watch as CompanionWatch
import Json.Decode as Decode
import Pebble.Events as PebbleEvents
import Pebble.Platform as PebblePlatform
import Pebble.Storage as PebbleStorage
import Pebble.Time as PebbleTime
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources
import Pebble.WatchInfo as WatchInfo


storeWatchSeconds : Int
storeWatchSeconds =
    1


storeQuoteSeconds : Int
storeQuoteSeconds =
    2


storeQuoteText : Int
storeQuoteText =
    3


storeWatchBackground : Int
storeWatchBackground =
    4


storeWatchForeground : Int
storeWatchForeground =
    5


storeQuoteBackground : Int
storeQuoteBackground =
    6


storeQuoteTextColor : Int
storeQuoteTextColor =
    7


defaultWatchSeconds : Int
defaultWatchSeconds =
    5


defaultQuoteSeconds : Int
defaultQuoteSeconds =
    3


defaultQuote : String
defaultQuote =
    "Make today count."


type Phase
    = ShowWatch
    | ShowQuote


type alias Point =
    { x : Int
    , y : Int
    }


type alias Rect =
    { x : Int
    , y : Int
    , w : Int
    , h : Int
    }


type alias TickMark =
    { from : Point
    , to : Point
    , width : Int
    }


type alias Hands =
    { hourTo : Point
    , minuteTo : Point
    , secondTo : Point
    , secondTail : Point
    }


{-| One wrapped quote line. Built when the quote or screen changes, not in `view`.
-}
type alias QuoteLine =
    { text : String
    , y : Int
    , h : Int
    }


{-| Screen-stable watch geometry. Built in `init` / `update`, not in `view`.
-}
type alias Layout =
    { center : Point
    , radius : Int
    , bezelInner : Int
    , railRadius : Int
    , hourTicks : List TickMark
    , minuteTicks : List Point
    , dateBox : Rect
    }


type alias Model =
    { screenW : Int
    , screenH : Int
    , displayShape : PebblePlatform.DisplayShape
    , colorMode : PebblePlatform.ColorCapability
    , now : Maybe PebbleTime.CurrentDateTime
    , quote : String
    , watchSeconds : Int
    , quoteSeconds : Int
    , phase : Phase
    , remainingSec : Int
    , layout : Layout
    , hands : Maybe Hands
    , dateLabel : String
    , quoteFont : UiResources.Font
    , quoteBox : Rect
    , quoteLines : List QuoteLine
    , caseColor : PebbleColor.Color
    , watchBackground : ThemeColor
    , watchForeground : ThemeColor
    , quoteBackground : ThemeColor
    , quoteText : ThemeColor
    }


type Msg
    = CurrentDateTime PebbleTime.CurrentDateTime
    | SecondChanged Int
    | MinuteChanged Int
    | HourChanged Int
    | FromPhone PhoneToWatch
    | LoadedWatchSeconds Int
    | LoadedQuoteSeconds Int
    | LoadedQuoteText String
    | LoadedWatchBackground Int
    | LoadedWatchForeground Int
    | LoadedQuoteBackground Int
    | LoadedQuoteTextColor Int
    | GotWatchColor WatchInfo.WatchColor


init : PebblePlatform.LaunchContext -> ( Model, Cmd Msg )
init context =
    let
        layout =
            buildLayout context.screen.width context.screen.height context.screen.shape
    in
    ( refreshQuoteLayout
        (refreshDraw
            { screenW = context.screen.width
            , screenH = context.screen.height
            , displayShape = context.screen.shape
            , colorMode = context.screen.colorMode
            , now = Nothing
            , quote = defaultQuote
            , watchSeconds = defaultWatchSeconds
            , quoteSeconds = defaultQuoteSeconds
            , phase = ShowWatch
            , remainingSec = defaultWatchSeconds
            , layout = layout
            , hands = Nothing
            , dateLabel = ""
            , quoteFont = UiResources.Quote28
            , quoteBox = { x = 0, y = 0, w = 1, h = 1 }
            , quoteLines = []
            , caseColor = WatchInfo.caseColor WatchInfo.UnknownColor
            , watchBackground = Cream
            , watchForeground = Black
            , quoteBackground = Cream
            , quoteText = Black
            }
        )
    , Cmd.batch
        [ PebbleTime.currentDateTime CurrentDateTime
        , CompanionWatch.sendWatchToPhone RequestSettings
        , PebbleStorage.readInt storeWatchSeconds LoadedWatchSeconds
        , PebbleStorage.readInt storeQuoteSeconds LoadedQuoteSeconds
        , PebbleStorage.readString storeQuoteText LoadedQuoteText
        , PebbleStorage.readInt storeWatchBackground LoadedWatchBackground
        , PebbleStorage.readInt storeWatchForeground LoadedWatchForeground
        , PebbleStorage.readInt storeQuoteBackground LoadedQuoteBackground
        , PebbleStorage.readInt storeQuoteTextColor LoadedQuoteTextColor
        , WatchInfo.getColor GotWatchColor
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CurrentDateTime value ->
            ( refreshDraw { model | now = Just value }, Cmd.none )

        SecondChanged second ->
            ( refreshAfterTick (tickPhase (setSecond second model)), Cmd.none )

        MinuteChanged minute ->
            ( refreshAfterTick (setMinute minute model), Cmd.none )

        HourChanged _ ->
            ( model, PebbleTime.currentDateTime CurrentDateTime )

        FromPhone message ->
            updateFromPhone message model

        LoadedWatchSeconds stored ->
            ( applyWatchSeconds stored model, Cmd.none )

        LoadedQuoteSeconds stored ->
            ( applyQuoteSeconds stored model, Cmd.none )

        LoadedQuoteText stored ->
            ( applyQuoteText stored model, Cmd.none )

        LoadedWatchBackground stored ->
            ( applyWatchBackground (themeColorFromCode stored Cream) model, Cmd.none )

        LoadedWatchForeground stored ->
            ( applyWatchForeground (themeColorFromCode stored Black) model, Cmd.none )

        LoadedQuoteBackground stored ->
            ( applyQuoteBackground (themeColorFromCode stored Cream) model, Cmd.none )

        LoadedQuoteTextColor stored ->
            ( applyQuoteTextColor (themeColorFromCode stored Black) model, Cmd.none )

        GotWatchColor color ->
            ( refreshDraw { model | caseColor = WatchInfo.caseColor color }, Cmd.none )


updateFromPhone : PhoneToWatch -> Model -> ( Model, Cmd Msg )
updateFromPhone message model =
    case message of
        SetMotivationalText text ->
            let
                next =
                    normalizeQuote text
            in
            ( applyQuoteText next model, PebbleStorage.writeString storeQuoteText next )

        SetWatchDisplaySeconds seconds ->
            let
                next =
                    clampSeconds seconds defaultWatchSeconds
            in
            ( applyWatchSeconds next model, PebbleStorage.writeInt storeWatchSeconds next )

        SetQuoteDisplaySeconds seconds ->
            let
                next =
                    clampSeconds seconds defaultQuoteSeconds
            in
            ( applyQuoteSeconds next model, PebbleStorage.writeInt storeQuoteSeconds next )

        SetWatchBackground color ->
            ( applyWatchBackground color model, PebbleStorage.writeInt storeWatchBackground (themeColorCode color) )

        SetWatchForeground color ->
            ( applyWatchForeground color model, PebbleStorage.writeInt storeWatchForeground (themeColorCode color) )

        SetQuoteBackground color ->
            ( applyQuoteBackground color model, PebbleStorage.writeInt storeQuoteBackground (themeColorCode color) )

        SetQuoteTextColor color ->
            ( applyQuoteTextColor color model, PebbleStorage.writeInt storeQuoteTextColor (themeColorCode color) )


applyWatchSeconds : Int -> Model -> Model
applyWatchSeconds seconds model =
    let
        next =
            clampSeconds seconds defaultWatchSeconds
    in
    refreshRemaining
        { model | watchSeconds = next }


applyQuoteSeconds : Int -> Model -> Model
applyQuoteSeconds seconds model =
    let
        next =
            clampSeconds seconds defaultQuoteSeconds
    in
    refreshRemaining
        { model | quoteSeconds = next }


applyQuoteText : String -> Model -> Model
applyQuoteText text model =
    refreshQuoteLayout { model | quote = normalizeQuote text }


applyWatchBackground : ThemeColor -> Model -> Model
applyWatchBackground color model =
    refreshDraw { model | watchBackground = color }


applyWatchForeground : ThemeColor -> Model -> Model
applyWatchForeground color model =
    refreshDraw { model | watchForeground = color }


applyQuoteBackground : ThemeColor -> Model -> Model
applyQuoteBackground color model =
    { model | quoteBackground = color }


applyQuoteTextColor : ThemeColor -> Model -> Model
applyQuoteTextColor color model =
    { model | quoteText = color }


themeColorCode : ThemeColor -> Int
themeColorCode color =
    case color of
        WatchBody ->
            1

        Cream ->
            2

        White ->
            3

        Black ->
            4

        Brass ->
            5

        Navy ->
            6

        Slate ->
            7

        Burgundy ->
            8

        Magenta ->
            9


themeColorFromCode : Int -> ThemeColor -> ThemeColor
themeColorFromCode code fallback =
    case code of
        1 ->
            WatchBody

        2 ->
            Cream

        3 ->
            White

        4 ->
            Black

        5 ->
            Brass

        6 ->
            Navy

        7 ->
            Slate

        8 ->
            Burgundy

        9 ->
            Magenta

        _ ->
            fallback


resolveThemeColor : ThemeColor -> PebbleColor.Color -> PebbleColor.Color
resolveThemeColor color caseColor =
    case color of
        WatchBody ->
            caseColor

        Cream ->
            PebbleColor.pastelYellow

        White ->
            PebbleColor.white

        Black ->
            PebbleColor.black

        Brass ->
            PebbleColor.brass

        Navy ->
            PebbleColor.oxfordBlue

        Slate ->
            PebbleColor.lightGray

        Burgundy ->
            PebbleColor.darkCandyAppleRed

        Magenta ->
            PebbleColor.magenta


normalizeQuote : String -> String
normalizeQuote text =
    let
        trimmed =
            String.trim text
    in
    if trimmed == "" then
        defaultQuote

    else
        trimmed


clampSeconds : Int -> Int -> Int
clampSeconds value fallback =
    if value < 1 then
        fallback

    else if value > 300 then
        300

    else
        value


refreshRemaining : Model -> Model
refreshRemaining model =
    let
        limit =
            phaseSeconds model
    in
    if model.remainingSec > limit then
        { model | remainingSec = limit }

    else if model.remainingSec < 1 then
        { model | remainingSec = limit }

    else
        model


phaseSeconds : Model -> Int
phaseSeconds model =
    case model.phase of
        ShowWatch ->
            model.watchSeconds

        ShowQuote ->
            model.quoteSeconds


tickPhase : Model -> Model
tickPhase model =
    if model.remainingSec <= 1 then
        case model.phase of
            ShowWatch ->
                { model | phase = ShowQuote, remainingSec = model.quoteSeconds }

            ShowQuote ->
                { model | phase = ShowWatch, remainingSec = model.watchSeconds }

    else
        { model | remainingSec = model.remainingSec - 1 }


setSecond : Int -> Model -> Model
setSecond second model =
    { model | now = updateField (\now -> { now | second = second }) model.now }


setMinute : Int -> Model -> Model
setMinute minute model =
    { model | now = updateField (\now -> { now | minute = minute }) model.now }


updateField : (PebbleTime.CurrentDateTime -> PebbleTime.CurrentDateTime) -> Maybe PebbleTime.CurrentDateTime -> Maybe PebbleTime.CurrentDateTime
updateField fn maybeNow =
    case maybeNow of
        Nothing ->
            Nothing

        Just now ->
            Just (fn now)


refreshDraw : Model -> Model
refreshDraw model =
    case model.now of
        Nothing ->
            { model | hands = Nothing, dateLabel = "" }

        Just now ->
            { model
                | hands = Just (buildHands model.layout now)
                , dateLabel = String.fromInt now.day
            }


refreshAfterTick : Model -> Model
refreshAfterTick model =
    case model.phase of
        ShowWatch ->
            refreshDraw model

        ShowQuote ->
            model


refreshQuoteLayout : Model -> Model
refreshQuoteLayout model =
    let
        bounds =
            quoteBounds model.screenW model.screenH model.displayShape

        font =
            pickQuoteFont model.quote bounds

        height =
            max 14 (UiResources.fontInfo font).height

        charWidth =
            max 6 (height // 2)

        maxChars =
            max 4 (bounds.w // charWidth)

        lines =
            wrapQuoteWords model.quote maxChars
                |> List.indexedMap
                    (\index text ->
                        { text = text
                        , y = bounds.y + index * height
                        , h = height
                        }
                    )
    in
    { model | quoteFont = font, quoteBox = bounds, quoteLines = lines }


subscriptions : Model -> Sub Msg
subscriptions _ =
    PebbleEvents.batch
        [ PebbleEvents.onSecondChange SecondChanged
        , PebbleEvents.onMinuteChange MinuteChanged
        , PebbleEvents.onHourChange HourChanged
        , CompanionWatch.onPhoneToWatch FromPhone
        ]


view : Model -> PebbleUi.UiNode
view model =
    case model.phase of
        ShowWatch ->
            watchOps model
                |> PebbleUi.toUiNode

        ShowQuote ->
            quoteOps model
                |> PebbleUi.toUiNode


watchOps : Model -> List PebbleUi.RenderOp
watchOps model =
    let
        dial =
            resolveThemeColor model.watchBackground model.caseColor

        ink =
            resolveThemeColor model.watchForeground model.caseColor
    in
    faceOps model.layout model.caseColor dial ink
        ++ List.map (hourTickOp ink) model.layout.hourTicks
        ++ List.map (minuteTickOp ink) model.layout.minuteTicks
        ++ dateOps model.layout.dateBox model.dateLabel ink
        ++ handOps model.layout.center model.hands ink (secondHandColor model)
        ++ [ PebbleUi.fillCircle model.layout.center 5 ink
           , PebbleUi.fillCircle model.layout.center 2 dial
           ]


quoteOps : Model -> List PebbleUi.RenderOp
quoteOps model =
    let
        background =
            resolveThemeColor model.quoteBackground model.caseColor

        textColor =
            resolveThemeColor model.quoteText model.caseColor
    in
    [ PebbleUi.clear background
    , PebbleUi.group
        (PebbleUi.context
            [ PebbleUi.textColor textColor ]
            (List.map (quoteLineOp model.quoteFont model.quoteBox) model.quoteLines)
        )
    ]


quoteLineOp : UiResources.Font -> Rect -> QuoteLine -> PebbleUi.RenderOp
quoteLineOp font box line =
    PebbleUi.text font
        PebbleUi.defaultTextOptions
        { x = box.x
        , y = line.y
        , w = box.w
        , h = line.h
        }
        line.text


wrapQuoteWords : String -> Int -> List String
wrapQuoteWords quote maxChars =
    quote
        |> String.words
        |> List.foldl (accQuoteWord maxChars) []
        |> List.reverse


accQuoteWord : Int -> String -> List String -> List String
accQuoteWord maxChars word lines =
    case lines of
        [] ->
            [ word ]

        current :: rest ->
            if String.length current + 1 + String.length word <= maxChars then
                (current ++ " " ++ word) :: rest

            else
                word :: lines


{-| Largest packed font that still fits the quote box on this screen.
-}
quoteFontCandidates : List UiResources.Font
quoteFontCandidates =
    [ UiResources.Quote42
    , UiResources.Quote28
    , UiResources.Quote24
    , UiResources.DefaultFont
    ]


pickQuoteFont : String -> Rect -> UiResources.Font
pickQuoteFont quote bounds =
    pickFirstFitting quote bounds quoteFontCandidates


pickFirstFitting : String -> Rect -> List UiResources.Font -> UiResources.Font
pickFirstFitting quote bounds fonts =
    case fonts of
        [] ->
            UiResources.DefaultFont

        font :: rest ->
            if fontFitsQuote quote bounds font then
                font

            else
                pickFirstFitting quote bounds rest


fontFitsQuote : String -> Rect -> UiResources.Font -> Bool
fontFitsQuote quote bounds font =
    let
        height =
            max 14 (UiResources.fontInfo font).height

        charWidth =
            max 6 (height // 2)

        maxChars =
            max 4 (bounds.w // charWidth)

        lineCount =
            List.length (wrapQuoteWords quote maxChars)
    in
    lineCount * height <= bounds.h


quoteBounds : Int -> Int -> PebblePlatform.DisplayShape -> Rect
quoteBounds screenW screenH displayShape =
    let
        inset =
            if PebblePlatform.displayShapeIsRound displayShape then
                max 22 (screenW // 6)

            else
                10
    in
    { x = inset
    , y = inset
    , w = max 48 (screenW - (inset * 2))
    , h = max 48 (screenH - (inset * 2))
    }


faceOps : Layout -> PebbleColor.Color -> PebbleColor.Color -> PebbleColor.Color -> List PebbleUi.RenderOp
faceOps layout letterbox dial ink =
    [ PebbleUi.clear letterbox
    , PebbleUi.fillCircle layout.center layout.radius dial
    , PebbleUi.circle layout.center layout.radius ink
    , PebbleUi.circle layout.center layout.bezelInner ink
    , PebbleUi.circle layout.center layout.railRadius ink
    ]


hourTickOp : PebbleColor.Color -> TickMark -> PebbleUi.RenderOp
hourTickOp ink tick =
    PebbleUi.group
        (PebbleUi.context
            [ PebbleUi.strokeColor ink
            , PebbleUi.strokeWidth tick.width
            ]
            [ PebbleUi.line tick.from tick.to ink ]
        )


minuteTickOp : PebbleColor.Color -> Point -> PebbleUi.RenderOp
minuteTickOp ink point =
    PebbleUi.pixel point ink


dateOps : Rect -> String -> PebbleColor.Color -> List PebbleUi.RenderOp
dateOps box dateLabel ink =
    if dateLabel == "" then
        []

    else
        [ PebbleUi.rect box ink
        , PebbleUi.group
            (PebbleUi.context
                [ PebbleUi.textColor ink ]
                [ PebbleUi.text UiResources.DefaultFont
                    (PebbleUi.alignCenter PebbleUi.defaultTextOptions)
                    box
                    dateLabel
                ]
            )
        ]


secondHandColor : Model -> PebbleColor.Color
secondHandColor model =
    if PebblePlatform.colorCapabilityIsColor model.colorMode then
        PebbleColor.folly

    else
        resolveThemeColor model.watchForeground model.caseColor


handOps : Point -> Maybe Hands -> PebbleColor.Color -> PebbleColor.Color -> List PebbleUi.RenderOp
handOps center maybeHands ink secondColor =
    case maybeHands of
        Nothing ->
            []

        Just hands ->
            [ strokeLine center hands.hourTo 4 ink
            , strokeLine center hands.minuteTo 2 ink
            , PebbleUi.group
                (PebbleUi.context
                    [ PebbleUi.strokeColor secondColor
                    , PebbleUi.strokeWidth 1
                    ]
                    [ PebbleUi.line center hands.secondTo secondColor
                    , PebbleUi.line center hands.secondTail secondColor
                    ]
                )
            ]


strokeLine : Point -> Point -> Int -> PebbleColor.Color -> PebbleUi.RenderOp
strokeLine from to width color =
    PebbleUi.group
        (PebbleUi.context
            [ PebbleUi.strokeColor color
            , PebbleUi.strokeWidth width
            ]
            [ PebbleUi.line from to color ]
        )


buildLayout : Int -> Int -> PebblePlatform.DisplayShape -> Layout
buildLayout screenW screenH displayShape =
    let
        centerX =
            screenW // 2

        centerY =
            screenH // 2

        center =
            { x = centerX, y = centerY }

        -- Keep 1px so the stroked outer circle is not clipped at the last column.
        edgePad =
            if PebblePlatform.displayShapeIsRound displayShape then
                3

            else
                1

        radius =
            max 28 ((min screenW screenH // 2) - edgePad)

        boxW =
            22

        boxH =
            16
    in
    { center = center
    , radius = radius
    , bezelInner = radius - 3
    , railRadius = max 16 (radius - 18)
    , hourTicks = List.map (hourTick center radius) hourTickIndexes
    , minuteTicks = List.map (minuteTick center radius) minuteTickIndexes
    , dateBox =
        { x = centerX + ((radius * 42) // 100) - (boxW // 2)
        , y = centerY - (boxH // 2)
        , w = boxW
        , h = boxH
        }
    }


buildHands : Layout -> PebbleTime.CurrentDateTime -> Hands
buildHands layout now =
    let
        hourIndex =
            modBy 60 ((modBy 12 now.hour) * 5 + (now.minute // 12))

        minuteIndex =
            modBy 60 now.minute

        secondIndex =
            modBy 60 now.second

        hourLen =
            (layout.radius * 54) // 100

        minuteLen =
            (layout.radius * 78) // 100

        secondLen =
            (layout.radius * 84) // 100

        secondTail =
            (layout.radius * 18) // 100
    in
    { hourTo = handPoint layout.center hourLen hourIndex
    , minuteTo = handPoint layout.center minuteLen minuteIndex
    , secondTo = handPoint layout.center secondLen secondIndex
    , secondTail = handPoint layout.center secondTail (secondIndex + 30)
    }


hourTickIndexes : List Int
hourTickIndexes =
    [ 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55 ]


minuteTickIndexes : List Int
minuteTickIndexes =
    List.filter (\index -> modBy 5 index /= 0) (List.range 0 59)


hourTick : Point -> Int -> Int -> TickMark
hourTick center radius index =
    let
        outer =
            radius - 5

        inner =
            if isCardinal index then
                radius - 16

            else
                radius - 11

        width =
            if isCardinal index then
                3

            else
                2
    in
    { from = handPoint center inner index
    , to = handPoint center outer index
    , width = width
    }


minuteTick : Point -> Int -> Int -> Point
minuteTick center radius index =
    handPoint center (radius - 7) index


isCardinal : Int -> Bool
isCardinal index =
    index == 0 || index == 15 || index == 30 || index == 45


handPoint : Point -> Int -> Int -> Point
handPoint center length index =
    let
        ( unitX, unitY ) =
            unit60 index
    in
    { x = center.x + (unitX * length) // 1000
    , y = center.y + (unitY * length) // 1000
    }


unit60 : Int -> ( Int, Int )
unit60 index =
    case modBy 60 index of
        0 ->
            ( 0, -1000 )

        1 ->
            ( 105, -995 )

        2 ->
            ( 208, -978 )

        3 ->
            ( 309, -951 )

        4 ->
            ( 407, -914 )

        5 ->
            ( 500, -866 )

        6 ->
            ( 588, -809 )

        7 ->
            ( 669, -743 )

        8 ->
            ( 743, -669 )

        9 ->
            ( 809, -588 )

        10 ->
            ( 866, -500 )

        11 ->
            ( 914, -407 )

        12 ->
            ( 951, -309 )

        13 ->
            ( 978, -208 )

        14 ->
            ( 995, -105 )

        15 ->
            ( 1000, 0 )

        16 ->
            ( 995, 105 )

        17 ->
            ( 978, 208 )

        18 ->
            ( 951, 309 )

        19 ->
            ( 914, 407 )

        20 ->
            ( 866, 500 )

        21 ->
            ( 809, 588 )

        22 ->
            ( 743, 669 )

        23 ->
            ( 669, 743 )

        24 ->
            ( 588, 809 )

        25 ->
            ( 500, 866 )

        26 ->
            ( 407, 914 )

        27 ->
            ( 309, 951 )

        28 ->
            ( 208, 978 )

        29 ->
            ( 105, 995 )

        30 ->
            ( 0, 1000 )

        31 ->
            ( -105, 995 )

        32 ->
            ( -208, 978 )

        33 ->
            ( -309, 951 )

        34 ->
            ( -407, 914 )

        35 ->
            ( -500, 866 )

        36 ->
            ( -588, 809 )

        37 ->
            ( -669, 743 )

        38 ->
            ( -743, 669 )

        39 ->
            ( -809, 588 )

        40 ->
            ( -866, 500 )

        41 ->
            ( -914, 407 )

        42 ->
            ( -951, 309 )

        43 ->
            ( -978, 208 )

        44 ->
            ( -995, 105 )

        45 ->
            ( -1000, 0 )

        46 ->
            ( -995, -105 )

        47 ->
            ( -978, -208 )

        48 ->
            ( -951, -309 )

        49 ->
            ( -914, -407 )

        50 ->
            ( -866, -500 )

        51 ->
            ( -809, -588 )

        52 ->
            ( -743, -669 )

        53 ->
            ( -669, -743 )

        54 ->
            ( -588, -809 )

        55 ->
            ( -500, -866 )

        56 ->
            ( -407, -914 )

        57 ->
            ( -309, -951 )

        58 ->
            ( -208, -978 )

        _ ->
            ( -105, -995 )


main : Program Decode.Value Model Msg
main =
    PebblePlatform.watchface
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
