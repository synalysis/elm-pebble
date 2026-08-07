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
import ExamplesCatalog exposing (Example)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (a, div, h1, h2, img, li, p, section, span, text, ul)
import Html.Attributes exposing (alt, attribute, href, rel, src, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route exposing (Route)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Svg
import Svg.Attributes as SvgAttr
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, hover, md, sm)
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
            { url = [ "images", "examples", "watchface-tangram-time.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "Elm Pebble — Pebble watch faces and apps in Elm"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Write Pebble watchfaces and tiny apps in Elm. Open templates in the browser IDE, run the emulator, then install on a Pebble."
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
                , staticBelowHero ()
                ]
            ]
        ]
    }


{-| Desire-first sections, then architecture for curious engineers.
-}
staticBelowHero : () -> Html.Html msg
staticBelowHero _ =
    div []
        [ examplesTeaser
        , audiencePaths
        , productLoop
        , section
            [ classes [ Tw.mt s12 ] ]
            [ h2
                [ classes
                    [ Tw.text_n3xl
                    , Tw.font_semibold
                    , Tw.tracking_tight
                    ]
                ]
                [ text "From idea to wrist" ]
            , p
                [ classes
                    [ Tw.mt s4
                    , Tw.text_base
                    , Tw.text_color (gray s600)
                    , dark [ Tw.text_color (gray s400) ]
                    ]
                ]
                [ text "Pebble apps are not web pages: there is no browser on the watch. You write Elm that compiles to C and drives Pebble's native UI." ]
            , ul
                [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s5, md [ Tw.grid_cols_3 ] ] ]
                [ workflowStep "1. Start from a template"
                    [ text "Open the IDE and clone YES, Tangram Time, Digital, 2048, or another working project instead of an empty tree." ]
                , workflowStep "2. Play in Elm"
                    [ text "Describe the screen with Elm and the Pebble UI API; the compiler turns that into native draw code — not HTML or CSS on the watch." ]
                , workflowStep "3. Try it on hardware"
                    [ text "Build with the Pebble SDK, run the emulator, then install on a "
                    , externalLink "https://repebble.com/" "Pebble"
                    , text " and see how it feels on your wrist."
                    ]
                ]
            ]
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
                [ featureItem "Elm to native Pebble apps"
                    [ text "Write Elm and compile to C code that runs on the Pebble SDK instead of a browser runtime." ]
                , featureItem "Typed Pebble UI"
                    [ text "Build watch screens with Elm data structures for text, images, shapes, layout, colors, and resources." ]
                , featureItem "Companion communication"
                    [ text "Define shared protocol types for watch-to-phone messages, including AppMessage-style data flow." ]
                , featureItem "Project templates"
                    [ text "Start from working watchface, companion app, and game templates instead of assembling the structure by hand." ]
                , featureItem "Hosted and local IDE"
                    [ text "Edit, inspect, and build projects at ide.elm-pebble.dev or run the same IDE locally with Docker." ]
                , featureItem "Hardware-oriented loop"
                    [ text "Use the Pebble SDK and emulator, then install on "
                    , externalLink "https://repebble.com/" "Pebble"
                    , text " watches with the companion app and appstore."
                    ]
                ]
            ]
        , section
            [ classes [ Tw.mt s12 ] ]
            [ div
                [ classes [ Tw.flex, Tw.flex_col, Tw.gap s4 ] ]
                [ Route.Examples
                    |> Route.link
                        [ classes linkClasses ]
                        [ text "Browse all examples" ]
                , Route.GettingStarted
                    |> Route.link
                        [ classes linkClasses ]
                        [ text "Getting started with Elm Pebble" ]
                , Route.Tutorial__WatchfaceTutorialComplete
                    |> Route.link
                        [ classes linkClasses ]
                        [ text "Read the watchface tutorial" ]
                , Route.Articles__WhyElmForPebble
                    |> Route.link
                        [ classes linkClasses ]
                        [ text "Why Elm fits Pebble watchfaces and apps" ]
                , Route.FAQ
                    |> Route.link
                        [ classes linkClasses ]
                        [ text "Frequently asked questions" ]
                ]
            , p
                [ classes [ Tw.mt s4, Tw.text_base, Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
                [ text "Open the hosted IDE to create a project, or clone the repository and run docker compose up -d for a local workspace." ]
            ]
        ]


linkClasses : List Tw.Tailwind
linkClasses =
    [ Tw.inline_flex
    , Tw.items_center
    , Tw.text_base
    , Tw.font_semibold
    , Tw.text_color (blue s600)
    , hover [ Tw.text_color (blue s700) ]
    , dark [ Tw.text_color (blue s400) ]
    ]


examplesTeaser : Html.Html msg
examplesTeaser =
    section
        [ classes [ Tw.mt s12 ] ]
        [ div
            [ classes [ Tw.flex, Tw.flex_wrap, Tw.items_end, Tw.justify_between, Tw.gap s4 ] ]
            [ div []
                [ h2
                    [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                    [ text "Built with Elm Pebble" ]
                , p
                    [ classes [ Tw.mt s3, Tw.max_w s96, Tw.text_lg, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                    [ text "Real templates you can open tonight — not mockups." ]
                ]
            , Route.Examples
                |> Route.link
                    [ classes linkClasses ]
                    [ text "See all examples" ]
            ]
        , div
            [ classes
                [ Tw.mt s6
                , Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s5
                , sm [ Tw.grid_cols_2 ]
                , md [ Tw.grid_cols_4 ]
                ]
            ]
            (List.map teaserCard (List.take 4 ExamplesCatalog.featured))
        ]


teaserCard : Example -> Html.Html msg
teaserCard example =
    a
        [ href (ExamplesCatalog.ideTemplateUrl example.templateKey)
        , target "_blank"
        , rel "noreferrer"
        , classes
            [ Tw.flex
            , Tw.flex_col
            , Tw.overflow_hidden
            , Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.shadow_lg
            , Tw.raw "hover:shadow-xl transition-shadow"
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ div
            [ classes
                [ Tw.flex
                , Tw.items_center
                , Tw.justify_center
                , Tw.bg_color (slate s950)
                , Tw.px s4
                , Tw.py s6
                ]
            ]
            [ img
                [ src example.image
                , alt (example.title ++ " watch screen")
                , classes [ Tw.raw "h-36 w-auto max-w-full", Tw.rounded_lg, Tw.shadow_lg ]
                ]
                []
            ]
        , div
            [ classes [ Tw.p s4 ] ]
            [ h2 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text example.title ]
            , p
                [ classes [ Tw.mt s2, Tw.text_sm, Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
                [ text example.blurb ]
            , span
                [ classes
                    [ Tw.mt s3
                    , Tw.inline_flex
                    , Tw.text_sm
                    , Tw.font_semibold
                    , Tw.text_color (blue s600)
                    , dark [ Tw.text_color (blue s400) ]
                    ]
                ]
                [ text "Open in IDE →" ]
            ]
        ]


audiencePaths : Html.Html msg
audiencePaths =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "Pick your on-ramp" ]
        , div
            [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s5, md [ Tw.grid_cols_2 ] ] ]
            [ pathCard "I know Elm"
                "Open a template, skim the packages, and compile watch Elm to C with the same TEA habits you already use."
                [ ( Route.Examples, "Browse templates" )
                , ( Route.Packages, "Package docs" )
                ]
            , pathCard "New to Elm"
                "Pebble projects are a friendly place to learn: small scope, wearable feedback, and the same architecture as browser Elm."
                [ ( Route.Articles__WhyElmForPebble, "Why Elm for Pebble" )
                , ( Route.Tutorial__WatchfaceTutorialComplete, "Watchface tutorial" )
                ]
            ]
        ]


pathCard : String -> String -> List ( Route, String ) -> Html.Html msg
pathCard title description links =
    div
        [ classes
            [ Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s6
            , Tw.shadow_lg
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ h2 [ classes [ Tw.text_n2xl, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes [ Tw.mt s3, Tw.text_base, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text description ]
        , div
            [ classes [ Tw.mt s5, Tw.flex, Tw.flex_col, Tw.gap s3 ] ]
            (List.map
                (\( route_, label ) ->
                    Route.link [ classes linkClasses ] [ text label ] route_
                )
                links
            )
        ]


productLoop : Html.Html msg
productLoop =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "Edit in the browser, see it on the watch" ]
        , p
            [ classes [ Tw.mt s4, Tw.max_w s96, Tw.text_lg, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text "The hosted IDE pairs Elm editing with an emulator and debugger so you can feel the loop before you flash hardware." ]
        , div
            [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s5, md [ Tw.grid_cols_2 ] ] ]
            [ div
                [ classes
                    [ Tw.overflow_hidden
                    , Tw.rounded_n2xl
                    , Tw.border
                    , Tw.border_color (gray s200)
                    , Tw.bg_simple white
                    , Tw.shadow_lg
                    , dark [ Tw.border_color (slate s800), Tw.bg_color (slate s900) ]
                    ]
                ]
                [ img
                    [ src "/images/light-editor.png"
                    , alt "Elm Pebble IDE editor"
                    , classes [ Tw.w_full, Tw.h_auto ]
                    ]
                    []
                , p
                    [ classes [ Tw.p s4, Tw.text_sm, Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
                    [ text "Edit watch, protocol, and phone Elm in one workspace." ]
                ]
            , div
                [ classes
                    [ Tw.overflow_hidden
                    , Tw.rounded_n2xl
                    , Tw.border
                    , Tw.border_color (gray s200)
                    , Tw.bg_simple white
                    , Tw.shadow_lg
                    , dark [ Tw.border_color (slate s800), Tw.bg_color (slate s900) ]
                    ]
                ]
                [ div
                    [ classes
                        [ Tw.flex
                        , Tw.items_center
                        , Tw.justify_center
                        , Tw.bg_color (slate s950)
                        , Tw.px s6
                        , Tw.py s10
                        ]
                    ]
                    [ img
                        [ src "/images/examples/watchface-tangram-time.png"
                        , alt "Tangram Time watchface preview"
                        , classes [ Tw.raw "h-48 w-auto", Tw.rounded_lg, Tw.shadow_lg ]
                        ]
                        []
                    ]
                , p
                    [ classes [ Tw.p s4, Tw.text_sm, Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
                    [ text "Templates ship as working faces and games you can wear." ]
                ]
            ]
        ]


hero : Html.Html msg
hero =
    section
        [ classes
            [ Tw.overflow_hidden
            , Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.shadow_lg
            , Tw.raw "site-hero-panel"
            , dark [ Tw.border_color (slate s800) ]
            ]
        ]
        [ div
            [ classes [ Tw.raw "site-hero-layout site-hero-layout-wide" ] ]
            [ div
                [ classes [ Tw.raw "site-hero-intro" ] ]
                [ heroStrip
                , div
                    [ classes [ Tw.raw "site-hero-headlines" ] ]
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
                        [ text "Wearable Elm for the Pebble revival." ]
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
                    ]
                ]
            , p
                [ classes
                    [ Tw.mt s6
                    , Tw.text_lg
                    , Tw.text_color (gray s700)
                    , dark [ Tw.text_color (gray s300) ]
                    ]
                ]
                [ text "Write a watchface in a calm, typed language — run it in the browser IDE, then on a Pebble. Same Elm Architecture you may know from the web, aimed at a tiny round screen." ]
            , div
                [ classes [ Tw.mt s6, Tw.flex, Tw.flex_wrap, Tw.items_center, Tw.gap s3 ] ]
                [ a
                    [ href "https://ide.elm-pebble.dev"
                    , rel "noreferrer"
                    , classes
                        [ Tw.inline_flex
                        , Tw.rounded_lg
                        , Tw.bg_color (blue s600)
                        , Tw.px s6
                        , Tw.py s3
                        , Tw.font_semibold
                        , Tw.text_simple white
                        , Tw.shadow_lg
                        , Tw.transition_colors
                        , Tw.raw "hover:bg-blue-700"
                        ]
                    ]
                    [ text "Open the IDE" ]
                , Route.Examples
                    |> Route.link
                        [ classes
                            [ Tw.inline_flex
                            , Tw.rounded_lg
                            , Tw.border
                            , Tw.border_color (gray s300)
                            , Tw.bg_simple white
                            , Tw.px s6
                            , Tw.py s3
                            , Tw.font_semibold
                            , Tw.text_color (slate s900)
                            , Tw.shadow_sm
                            , Tw.raw "hover:bg-gray-50"
                            , dark
                                [ Tw.border_color (slate s600)
                                , Tw.bg_color (slate s800)
                                , Tw.text_color (gray s100)
                                , Tw.raw "hover:bg-slate-700"
                                ]
                            ]
                        ]
                        [ text "See examples" ]
                ]
            , betaNotice
            ]
        ]


betaNotice : Html.Html msg
betaNotice =
    div
        [ classes
            [ Tw.mt s6
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (blue s200)
            , Tw.bg_color (blue s100)
            , Tw.px s4
            , Tw.py s3
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
            [ span [ classes [ Tw.font_semibold ] ] [ text "Beta: " ]
            , text "Compiler, IDE, packages, and APIs can still change while the project settles."
            ]
        ]


heroStrip : Html.Html msg
heroStrip =
    div
        [ classes [ Tw.raw "site-hero-strip" ] ]
        (List.map heroStripImage
            [ ( "/images/examples/watchface-yes.png", "YES watchface" )
            , ( "/images/examples/watchface-tangram-time.png", "Tangram Time watchface" )
            , ( "/images/examples/watchface-digital.png", "Digital watchface" )
            ]
        )


heroStripImage : ( String, String ) -> Html.Html msg
heroStripImage ( url, label ) =
    img
        [ src url
        , alt label
        , attribute "loading" "eager"
        , classes
            [ Tw.rounded_lg
            , Tw.border
            , Tw.border_color (slate s700)
            , Tw.shadow_lg
            , Tw.raw "site-hero-strip-shot"
            ]
        ]
        []


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


featureItem : String -> List (Html.Html msg) -> Html.Html msg
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
            description
        ]


externalLink : String -> String -> Html.Html msg
externalLink url label =
    a
        [ href url
        , target "_blank"
        , rel "noreferrer"
        , classes
            [ Tw.font_semibold
            , Tw.text_color (blue s700)
            , dark [ Tw.text_color (blue s400) ]
            ]
        ]
        [ text label ]


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


workflowStep : String -> List (Html.Html msg) -> Html.Html msg
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
            description
        ]
