module Route.FAQ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, a, div, h1, h2, li, p, section, span, text, ul)
import Html.Attributes exposing (href, rel, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s600, s700, s8, s800, s900, s950, slate, white)
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
            , alt = "Elm Pebble FAQ"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Frequently asked questions about Elm Pebble, the return of Pebble hardware, Elm on the watch, and how the toolchain fits together."
        , locale = Nothing
        , title = "Frequently asked questions"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "FAQ | Elm Pebble"
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
                    , Tw.raw "max-w-3xl"
                    , md [ Tw.px s10, Tw.py s16 ]
                    ]
                ]
                [ hero
                , faqEntry "Hasn't Pebble been bought by Fitbit many years ago?"
                    [ paragraph "Yes. Fitbit acquired Pebble's assets in 2016 and later shut down Pebble cloud services, including the original CloudPebble IDE. Google bought Fitbit in 2021. That chapter is over for the original product line."
                    , paragraph "What people wear and develop for today is also a new Pebble hardware and software effort—watches, a companion app, an appstore, and open tooling—sold and documented under the Pebble name again. Elm Pebble is built for that current ecosystem and appstore path."
                    , paragraph "That does not mean Elm Pebble only targets post-revival hardware. The Pebble SDK still defines platform targets from the pre-Fitbit era onward. You can build for Aplite (original black-and-white Pebble and Pebble Steel) as well as later models. In the IDE you pick which platforms a project supports; Aplite is optional because those watches are tight on flash and RAM."
                    , p [ classes answerLinkClasses ]
                        [ text "See the "
                        , externalLink "https://repebble.com/" "Pebble ecosystem"
                        , text " site for the revival project itself."
                        ]
                    ]
                , faqEntry "What is Elm Pebble?"
                    [ paragraph "Elm Pebble is an open-source platform for building Pebble watchfaces and apps primarily in Elm. It includes the hosted IDE, the elmc compiler that turns watch Elm into C for the Pebble SDK, Elm packages for watch and companion APIs, project templates, emulator support, and documentation."
                    , p [ classes answerLinkClasses ]
                        [ Route.GettingStarted
                            |> Route.link [ classes linkClasses ] [ text "Getting started" ]
                        , text " is the shortest on-ramp; the "
                        , Route.Ide
                            |> Route.link [ classes linkClasses ] [ text "IDE overview" ]
                        , text " explains how the pieces connect."
                        ]
                    ]
                , faqEntry "Is Elm Pebble vibe coded?"
                    [ paragraph "\"Vibe coded\" usually means a prototype held together without structure—no tests, no docs, no clear architecture. Elm Pebble is not that: there is a defined compiler pipeline, package contracts, project templates, and a large automated test suite across elmc, the IDE, and the site."
                    , paragraph "A separate question is how much was written with AI assistance. That is substantial; see the next answer. The distinction matters: AI helped build a documented system, not an unmaintainable one-off."
                    ]
                , faqEntry "Was Elm Pebble built with AI?"
                    [ paragraph "To a large degree, yes. Much of the compiler, IDE, runtime shims, documentation, and this site were produced or heavily revised with AI coding tools. Without that support, the project in its current form would not exist—it would be far smaller or still aspirational."
                    , paragraph "Human direction still matters: architecture choices, Pebble and Elm semantics, review, tests, and what gets merged are intentional. Treat AI-generated code like any other contribution—it must pass tests and fit the contracts. If something looks wrong, report it; that feedback is part of how the project stays honest."
                    ]
                , faqEntry "How does Elm Pebble compare to CloudPebble?"
                    [ paragraph "CloudPebble is Pebble's official browser-based IDE again: write watch apps in C or JavaScript, manage resources in a UI instead of hand-editing JSON, compile without a local Linux toolchain, and install through the Pebble account flow. The classic service shut down with Fitbit-era infrastructure; it is back under the current Pebble effort."
                    , p [ classes answerLinkClasses ]
                        [ externalLink "https://cloudpebble.repebble.com/" "CloudPebble"
                        , text " is the place to go if you want Pebble's official in-browser C or JavaScript workflow with zero local SDK setup."
                        ]
                    , paragraph "Elm Pebble is a separate, independent open-source stack—not CloudPebble with a new skin. You author Elm on the watch and companion; elmc generates C and the normal Pebble SDK binary. The hosted IDE adds Elm-specific tooling: templates, package docs, emulators, and debugger integration aimed at the Elm workflow."
                    , paragraph "Both offer \"develop in the browser\" convenience. Choose CloudPebble for official C or JavaScript development on Pebble's infrastructure; choose Elm Pebble if you want Elm's type system and architecture on watch and phone, and are fine with an independent beta project that still lands on the same Pebble binaries."
                    ]
                , faqEntry "Why Elm?"
                    [ paragraph "Pebble apps are event-driven and state-heavy: ticks, buttons, battery changes, and phone messages all need a clear story for how data flows. Elm's model–message–update loop keeps that explicit, and the compiler rejects many protocol and UI mistakes before you flash a build."
                    , paragraph "You still write normal Elm on the companion side where browser and HTTP packages make sense. The watch side uses Elm Pebble packages that map to Pebble drawing and system APIs instead of the DOM."
                    , p [ classes answerLinkClasses ]
                        [ Route.Articles__WhyElmForPebble
                            |> Route.link [ classes linkClasses ] [ text "Why Elm fits Pebble watchfaces and apps" ]
                        , text " goes deeper for developers new to Elm."
                        ]
                    ]
                , faqEntry "Do I need a physical Pebble watch?"
                    [ paragraph "No. The IDE includes emulators so you can edit, build, and debug without hardware. A watch is still the best final check for layout, contrast, and how an interaction feels on your wrist."
                    , paragraph "When you are ready, install a build through the Pebble companion app and appstore in the current Pebble ecosystem—the same path as any other Pebble developer today."
                    ]
                , faqEntry "How does Elm Pebble relate to the original Pebble SDK?"
                    [ paragraph "You still rely on the Pebble SDK and toolchain to package, install, and run native apps on the watch. Elm Pebble sits above that layer for the parts you author in Elm: it type-checks watch code, generates C and shims, and wires companion protocols."
                    , paragraph "Think of it as a new language frontend for a familiar Pebble-shaped build pipeline, not a replacement for the SDK itself."
                    ]
                , faqEntry "Can I use regular Elm packages on the watch?"
                    [ paragraph "Only if they fit a watch target with no browser, filesystem, or network runtime. Packages that depend on elm/browser, elm/html, elm/http, or similar will not compile for the watch."
                    , paragraph "Use Elm Pebble packages for drawing, time, storage, vibration, and system state on the watch. Use ordinary Elm packages on the companion phone app where the standard compiler applies."
                    , p [ classes answerLinkClasses ]
                        [ Route.Packages
                            |> Route.link [ classes linkClasses ] [ text "Package docs" ]
                        , text " list what ships with Elm Pebble and how watch limits are described."
                        ]
                    ]
                , faqEntry "Do I need to write C?"
                    [ paragraph "You write Elm. elmc produces the C sources and Pebble integration glue; the IDE and SDK take it from there. You might read generated C when debugging a tough build issue, but it is not the language you author day to day."
                    ]
                , faqEntry "Is Elm Pebble affiliated with Pebble, Rebble, or the Elm project?"
                    [ paragraph "No. Elm Pebble is an independent open-source project developed by Synalysis. It is not affiliated with Core Devices, the Elm Software Foundation, or Pebble trademark owners, though it is built for today's Pebble ecosystem."
                    , paragraph "The Elm language and tooling are separate projects; Elm Pebble uses Elm and contributes compiler and package work back in the open, but it is not an official Elm Foundation product."
                    ]
                , faqEntry "Is it ready for production?"
                    [ paragraph "Elm Pebble is still in beta. The compiler, IDE, runtime packages, and public APIs can change while the project settles. Many templates and workflows already work end to end, but you should expect occasional churn and report issues you hit."
                    , paragraph "For experimenting, learning, and shipping small watchfaces or apps you are willing to maintain through updates, it is usable today. For hard guarantees about long-term API stability, treat the beta notice seriously."
                    ]
                , relatedLinks
                , backLink
                ]
            ]
        ]
    }


hero : Html msg
hero =
    section
        [ classes
            [ Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s8
            , Tw.shadow_lg
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ span
            [ classes
                [ Tw.inline_flex
                , Tw.rounded_lg
                , Tw.bg_color (blue s100)
                , Tw.px s3
                , Tw.py s2
                , Tw.text_base
                , Tw.font_semibold
                , Tw.text_color (blue s800)
                , dark
                    [ Tw.bg_color (blue s950)
                    , Tw.text_color (blue s200)
                    ]
                ]
            ]
            [ text "FAQ" ]
        , h1
            [ classes
                [ Tw.mt s6
                , Tw.text_n3xl
                , Tw.font_black
                , Tw.tracking_tight
                , md [ Tw.text_n4xl ]
                ]
            ]
            [ text "Frequently asked questions" ]
        , p
            [ classes
                [ Tw.mt s5
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "Straight answers about Pebble's history and return, legacy watches, AI's role in the project, CloudPebble, and why Elm is in the stack." ]
        ]


faqEntry : String -> List (Html msg) -> Html msg
faqEntry question answer =
    section
        [ classes
            [ Tw.mt s12
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
        (h2
            [ classes
                [ Tw.text_lg
                , Tw.font_semibold
                , Tw.tracking_tight
                , Tw.text_color (slate s900)
                , dark [ Tw.text_simple white ]
                ]
            ]
            [ text question ]
            :: answer
        )


paragraph : String -> Html msg
paragraph value =
    p
        [ classes
            [ Tw.mt s4
            , Tw.text_base
            , Tw.text_color (gray s700)
            , dark [ Tw.text_color (gray s300) ]
            ]
        ]
        [ text value ]


answerLinkClasses : List Tw.Tailwind
answerLinkClasses =
    [ Tw.mt s4, Tw.text_base ]


linkClasses : List Tw.Tailwind
linkClasses =
    [ Tw.font_semibold
    , Tw.text_color (blue s600)
    , dark [ Tw.text_color (blue s400) ]
    ]


externalLink : String -> String -> Html msg
externalLink url label =
    a
        [ href url
        , rel "noreferrer"
        , target "_blank"
        , classes linkClasses
        ]
        [ text label ]


relatedLinks : Html msg
relatedLinks =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "Read more" ]
        , ul
            [ classes
                [ Tw.mt s5
                , Tw.flex
                , Tw.flex_col
                , Tw.gap s3
                , Tw.list_disc
                , Tw.pl s6
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ li []
                [ Route.GettingStarted
                    |> Route.link [ classes linkClasses ] [ text "Getting started" ]
                ]
            , li []
                [ Route.Articles__WhyElmForPebble
                    |> Route.link [ classes linkClasses ] [ text "Why Elm fits Pebble" ]
                ]
            , li []
                [ Route.Tutorial__WatchfaceTutorialComplete
                    |> Route.link [ classes linkClasses ] [ text "Watchface tutorial walkthrough" ]
                ]
            , li []
                [ Route.Packages
                    |> Route.link [ classes linkClasses ] [ text "Package documentation" ]
                ]
            ]
        ]


backLink : Html msg
backLink =
    section
        [ classes [ Tw.mt s12 ] ]
        [ p
            [ classes [ Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
            [ Route.Index
                |> Route.link [ classes linkClasses ] [ text "Back to the home page" ]
            ]
        ]
