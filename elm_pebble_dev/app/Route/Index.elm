module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Cartesian as Wiring exposing (C)
import Cartesian.Layout as WiringLayout
import Cartesian.Layout.Svg as WiringLayoutSvg
import Diagram.Bound as WiringBound
import Diagram.Extent as WiringExtent
import Diagram.Layout.Config as WiringLayoutConfig
import Diagram.Svg as WiringSvg
import Diagram.Svg.Config as WiringSvgConfig
import Diagram.Vec2 as WiringVec2
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (div, h1, h2, img, li, node, p, section, span, text, ul)
import Html.Attributes exposing (alt, attribute, src, type_)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Svg
import Svg.Attributes as SvgAttr
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, hover, md)
import Tailwind.Theme exposing (blue, emerald, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s600, s700, s8, s800, s900, s950, s96, slate, white)
import UrlPath
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask FatalError Data
data =
    BackendTask.succeed {}


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head _ =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Elm Pebble"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "Elm Pebble — Pebble watch face tinkering with Elm"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Build Pebble watch faces and tiny apps in Elm with a tight feedback loop, typed state, and native Pebble output."
        , locale = Nothing
        , title = "Elm Pebble — Watch faces and apps in Elm"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "Elm Pebble | Watch faces & apps in Elm"
    , body =
        [ div
            [ classes
                [ Tw.min_h_screen
                , Tw.bg_color (gray s100)
                , Tw.text_color (slate s900)
                , Tw.antialiased
                , dark
                    [ Tw.bg_color (slate s950)
                    , Tw.text_color (gray s100)
                    ]
                ]
            ]
            [ div
                [ classes
                    [ Tw.mx_auto
                    , Tw.w_full
                    , Tw.px s6
                    , Tw.py s12
                    , Tw.leading_relaxed
                    , Tw.raw "max-w-6xl"
                    , md [ Tw.px s10, Tw.py s16 ]
                    ]
                ]
                [ hero
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes
                            [ Tw.text_n3xl
                            , Tw.font_semibold
                            , Tw.tracking_tight
                            ]
                        ]
                        [ text "Why bother (in a good way)" ]
                    , div
                        [ classes
                            [ Tw.mt s6
                            , Tw.grid
                            , Tw.grid_cols_1
                            , Tw.gap s5
                            , md [ Tw.grid_cols_3 ]
                            ]
                        ]
                        [ benefitCard "Sketch a face quickly" "Elm keeps UI experiments readable, so you can try a layout, adjust it, and keep moving without a pile of mystery state."
                        , benefitCard "Fewer “wait, why did that crash?” moments" "Typed messages and explicit updates make small watch apps easier to reason about as they grow."
                        , benefitCard "Make something people can wear" "Tweak colors, complications, and interaction details until the watch face feels right on real hardware."
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "The shape of the system" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.max_w s96, Tw.text_lg, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "Elm Pebble keeps the application loop and build pipeline explicit, so you can see where state, events, UI, and Pebble tooling fit together." ]
                    , div
                        [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s5, md [ Tw.grid_cols_2 ] ] ]
                        [ visualizationCard "Elm Architecture on the watch" "Messages come from Pebble events and subscriptions, update changes the model, and view redraws the Pebble UI from that model." teaDiagram
                        , visualizationCard "From Elm code to a Pebble app" "Elm Pebble branches the project into native C output for the Pebble SDK and JavaScript output for the phone-side companion app." toolchainDiagram
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Features" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.max_w s96, Tw.text_lg, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "Elm Pebble brings the parts you need for real Pebble projects into one Elm-first workflow." ]
                    , ul
                        [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s5, md [ Tw.grid_cols_3 ] ] ]
                        [ featureItem "Elm to native Pebble apps" "Write Elm and compile to C code that runs on the Pebble SDK instead of a browser runtime."
                        , featureItem "Typed Pebble UI" "Build watch screens with Elm data structures for text, images, shapes, layout, colors, and resources."
                        , featureItem "Companion communication" "Define shared protocol types for watch-to-phone messages, including AppMessage-style data flow."
                        , featureItem "Project templates" "Start from working watchface, companion app, and protocol templates instead of assembling the structure by hand."
                        , featureItem "Browser-based IDE" "Edit, inspect, and build projects from the Elm Pebble IDE with tooling shaped around Pebble apps."
                        , featureItem "Hardware-oriented loop" "Use the Pebble SDK, emulator, and real watches as the target for every iteration."
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "How Elm Pebble works" ]
                    , p
                        [ classes
                            [ Tw.mt s4
                            , Tw.text_base
                            , Tw.text_color (gray s600)
                            , dark [ Tw.text_color (gray s400) ]
                            ]
                        ]
                        [ text "Pebble apps are not web pages: there is no browser on the watch. You write Elm that compiles to C and drives Pebble's native UI. Anything that makes this site pretty in your desktop browser stays there—your watch never sees it." ]
                    , ul
                        [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s5, md [ Tw.grid_cols_3 ] ] ]
                        [ workflowStep "1. Start small" "Grab a minimal watch face or tiny app skeleton, then grow it one visible behavior at a time."
                        , workflowStep "2. Play in Elm" "Describe the screen with Elm and the Pebble UI API; the compiler turns that into native draw code—not HTML or CSS on the watch."
                        , workflowStep "3. Try it on hardware" "Build with the Pebble SDK, run the emulator or flash your watch, and see how the idea feels on the wrist."
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Who it is for" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.max_w s96, Tw.text_lg, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "Pebble fans, Elm-curious developers, and anyone who wants a calmer way to build watch faces and small wrist apps with explicit state and predictable updates." ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ div
                        [ classes [ Tw.flex, Tw.flex_col, Tw.gap s4 ] ]
                        [ Route.Ide
                            |> Route.link
                                [ classes
                                    [ Tw.inline_flex
                                    , Tw.items_center
                                    , Tw.text_base
                                    , Tw.font_semibold
                                    , Tw.text_color (blue s600)
                                    , hover [ Tw.text_color (blue s700) ]
                                    , dark [ Tw.text_color (blue s400), hover [ Tw.text_color (blue s300) ] ]
                                    ]
                                ]
                                [ text "How the elm-pebble IDE is built" ]
                        , Route.Articles__WhyElmForPebble
                            |> Route.link
                                [ classes
                                    [ Tw.inline_flex
                                    , Tw.items_center
                                    , Tw.text_base
                                    , Tw.font_semibold
                                    , Tw.text_color (blue s600)
                                    , hover [ Tw.text_color (blue s700) ]
                                    , dark [ Tw.text_color (blue s400), hover [ Tw.text_color (blue s300) ] ]
                                    ]
                                ]
                                [ text "Why Elm fits Pebble watchfaces and apps" ]
                        , Route.Tutorial__WatchfaceTutorialComplete
                            |> Route.link
                                [ classes
                                    [ Tw.inline_flex
                                    , Tw.items_center
                                    , Tw.text_base
                                    , Tw.font_semibold
                                    , Tw.text_color (blue s600)
                                    , hover [ Tw.text_color (blue s700) ]
                                    , dark [ Tw.text_color (blue s400), hover [ Tw.text_color (blue s300) ] ]
                                    ]
                                ]
                                [ text "Read the Watchface tutorial complete walkthrough" ]
                        ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_base, Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
                        [ text "Clone, run, and iterate from Elm code to an emulator or watch without losing the shape of your app." ]
                    ]
                ]
            ]
        ]
    }


hero : Html.Html msg
hero =
    section
        [ classes
            [ Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.px s8
            , Tw.py s12
            , Tw.shadow_lg
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ div
            [ classes
                [ Tw.flex
                , Tw.flex_col
                , Tw.items_center
                , Tw.gap s8
                , Tw.raw "md:flex-row md:items-start"
                ]
            ]
            [ heroImage
            , div
                [ classes [ Tw.w_full ] ]
                [ span
                    [ classes
                        [ Tw.inline_flex
                        , Tw.items_center
                        , Tw.rounded_lg
                        , Tw.bg_color (emerald s100)
                        , Tw.px s3
                        , Tw.py s2
                        , Tw.text_base
                        , Tw.font_semibold
                        , Tw.text_color (emerald s700)
                        , dark
                            [ Tw.bg_color (emerald s900)
                            , Tw.text_color (emerald s200)
                            ]
                        ]
                    ]
                    [ text "A nicer way to build Pebble watch faces." ]
                , h1
                    [ classes
                        [ Tw.mt s6
                        , Tw.text_n4xl
                        , Tw.font_black
                        , Tw.tracking_tight
                        , md [ Tw.text_n5xl ]
                        ]
                    ]
                    [ text "Pebble watch faces & apps in Elm." ]
                , p
                    [ classes
                        [ Tw.mt s5
                        , Tw.max_w s96
                        , Tw.text_lg
                        , Tw.text_color (gray s700)
                        , dark [ Tw.text_color (gray s300) ]
                        ]
                    ]
                    [ text "Elm Pebble gives Pebble developers a real language and a tight feedback loop: model your app in Elm, see it on a tiny round screen, and keep the logic understandable as the interface evolves." ]
                , betaNotice
                ]
            ]
        ]


betaNotice : Html.Html msg
betaNotice =
    div
        [ classes
            [ Tw.mt s6
            , Tw.max_w s96
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (blue s200)
            , Tw.bg_color (blue s100)
            , Tw.p s4
            , Tw.text_sm
            , Tw.text_color (slate s800)
            , dark
                [ Tw.border_color (blue s600)
                , Tw.bg_color (slate s800)
                , Tw.text_color (gray s200)
                ]
            ]
        ]
        [ p []
            [ span [ classes [ Tw.font_semibold ] ] [ text "Beta notice: " ]
            , text "Elm Pebble is still evolving. The compiler, IDE, runtime packages, and public APIs can change while the project settles."
            ]
        ]


heroImage : Html.Html msg
heroImage =
    node "picture"
        []
        [ node "source"
            [ attribute "srcset" "/pebble-elm.webp"
            , type_ "image/webp"
            ]
            []
        , img
            [ src "/pebble-elm.jpg"
            , alt "Pebble watch displaying an Elm Pebble watchface"
            , attribute "loading" "eager"
            , classes
                [ Tw.w_full
                , Tw.rounded_lg
                , Tw.border
                , Tw.border_color (gray s200)
                , Tw.shadow_lg
                , dark [ Tw.border_color (slate s800) ]
                , Tw.raw "max-w-56 md:max-w-64 object-cover"
                ]
            ]
            []
        ]


benefitCard : String -> String -> Html.Html msg
benefitCard title description =
    div
        [ classes
            [ Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s6
            , Tw.shadow_sm
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ h2 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes
                [ Tw.mt s3
                , Tw.text_base
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text description ]
        ]


featureItem : String -> String -> Html.Html msg
featureItem title description =
    li
        [ classes
            [ Tw.list_none
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s6
            , Tw.shadow_sm
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ h2 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes [ Tw.mt s3, Tw.text_base, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text description ]
        ]


visualizationCard : String -> String -> Html.Html msg -> Html.Html msg
visualizationCard title description graphic =
    div
        [ classes
            [ Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s6
            , Tw.shadow_sm
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ graphic
        , h2 [ classes [ Tw.mt s5, Tw.text_lg, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes [ Tw.mt s3, Tw.text_base, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text description ]
        ]


teaDiagram : Html.Html msg
teaDiagram =
    div
        [ diagramWrapperClasses ]
        [ wiringDiagramView teaWiring ]


toolchainDiagram : Html.Html msg
toolchainDiagram =
    div
        [ diagramWrapperClasses ]
        [ wiringDiagramView toolchainWiring ]


diagramWrapperClasses : Html.Attribute msg
diagramWrapperClasses =
    classes
        [ Tw.w_full
        , Tw.overflow_hidden
        , Tw.text_color (slate s700)
        , Tw.raw "[&>svg]:block [&>svg]:h-auto [&>svg]:max-w-full [&>svg]:w-full"
        , dark [ Tw.text_color (gray s200) ]
        ]


wiringDiagramView : C String -> Html.Html msg
wiringDiagramView diagram =
    let
        layout =
            WiringLayout.toLayoutWithConfig wiringLayoutConfig diagram
    in
    WiringSvg.view
        (WiringLayoutSvg.viewportFor layout)
        [ WiringLayoutSvg.toSvgWith wiringSvgConfig layout ]


teaWiring : C String
teaWiring =
    (Wiring.initWith 0 1 "Events"
        |> Wiring.aside (Wiring.initWith 0 1 "Sub")
    )
        |> Wiring.before (Wiring.initWith 2 1 "Msg")
        |> Wiring.before (Wiring.initWith 1 2 "Update")
        |> Wiring.before
            ((Wiring.init "Model"
                |> Wiring.before (Wiring.init "View")
                |> Wiring.before (Wiring.initWith 1 0 "Pebble UI")
             )
                |> Wiring.aside (Wiring.initWith 1 0 "Cmd")
            )


toolchainWiring : C String
toolchainWiring =
    Wiring.initWith 0 1 "Watch & Companion Elm"
        |> Wiring.before (Wiring.initWith 1 2 "Elm Pebble")
        |> Wiring.before
            ((Wiring.init "C output"
                |> Wiring.before (Wiring.initWith 1 2 "Pebble SDK")
                |> Wiring.before
                    (Wiring.initWith 1 0 "Emulator"
                        |> Wiring.aside (Wiring.initWith 1 0 "Watch")
                    )
             )
                |> Wiring.aside
                    (Wiring.init "JS output"
                        |> Wiring.before (Wiring.initWith 1 0 "Phone")
                    )
            )


wiringLayoutConfig : WiringLayoutConfig.Config String
wiringLayoutConfig =
    WiringLayoutConfig.default
        |> WiringLayoutConfig.setSpacing (WiringVec2.init 34 24)
        |> WiringLayoutConfig.setLeafExtent wiringBoxBound


wiringBoxBound : String -> WiringBound.Bound
wiringBoxBound label =
    let
        width =
            if String.length label > 16 then
                112

            else if String.length label > 10 then
                92

            else
                72

        height =
            if String.length label > 16 then
                56

            else
                38
    in
    WiringBound.init <|
        WiringExtent.init
            (WiringVec2.init 0 0)
            (WiringVec2.init width height)


wiringSvgConfig : WiringSvgConfig.Config String msg
wiringSvgConfig =
    WiringSvgConfig.forStringLabels
        |> WiringSvgConfig.withCellAttributesFunction wiringCellAttributes
        |> WiringSvgConfig.withTextAttributes
            [ SvgAttr.fill "#0f172a"
            , SvgAttr.stroke "none"
            , SvgAttr.fontSize "12px"
            , SvgAttr.fontWeight "700"
            ]


wiringCellAttributes : Maybe String -> List (Svg.Attribute msg)
wiringCellAttributes maybeLabel =
    case maybeLabel of
        Just label ->
            if List.member label [ "Events", "Sub", "Cmd", "Pebble UI", "Watch", "Emulator", "Phone" ] then
                [ SvgAttr.fill "#eff6ff"
                , SvgAttr.fillOpacity "1"
                , SvgAttr.stroke "#2563eb"
                , SvgAttr.strokeWidth "1.5"
                ]

            else
                [ SvgAttr.fill "#ecfdf5"
                , SvgAttr.fillOpacity "1"
                , SvgAttr.stroke "#059669"
                , SvgAttr.strokeWidth "1.5"
                ]

        Nothing ->
            [ SvgAttr.fill "none"
            , SvgAttr.stroke "none"
            ]


workflowStep : String -> String -> Html.Html msg
workflowStep heading description =
    li
        [ classes
            [ Tw.list_none
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s6
            , dark [ Tw.border_color (slate s800), Tw.bg_color (slate s900) ]
            ]
        ]
        [ h2 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text heading ]
        , p
            [ classes [ Tw.mt s3, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text description ]
        ]
