module Route.GettingStarted exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, a, div, h1, h2, li, p, pre, section, span, text, ul)
import Html.Attributes exposing (href, rel, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, emerald, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s600, s700, s8, s800, s900, s950, slate, white)
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
            , alt = "Getting started with Elm Pebble"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Start building Pebble watchfaces and apps in Elm with the hosted IDE, project templates, emulator, and package docs."
        , locale = Nothing
        , title = "Getting started with Elm Pebble"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "Getting started | Elm Pebble"
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
                , sectionBlock "Use the hosted IDE"
                    [ paragraph "The fastest way to try Elm Pebble is the hosted IDE. Sign in, create a project from a template, edit watch, protocol, and phone sources, then build and run in the emulator or debugger."
                    , externalButton "https://ide.elm-pebble.dev" "Open the IDE"
                    , paragraph "The IDE includes CodeMirror editing, elmc check/compile, Pebble SDK packaging, a debugger with watch and companion state, embedded and external emulators, optional browser WASM emulation, and MCP/ACP hooks for AI tools."
                    ]
                , sectionBlock "Pick a project template"
                    [ paragraph "New projects start from working templates instead of an empty tree. Common starting points include:"
                    , bulletList
                        [ "Starter — watch, protocol, and phone roots for a full app."
                        , "Watchface tutorial complete — the weather watchface walked through in the tutorial."
                        , "Watchfaces — digital, analog, YES, Tangram Time, and animated weather samples."
                        , "Companion demos — phone status, weather, calendar, geolocation, storage, settings, WebSocket, and timeline APIs."
                        , "Watch demos — accelerometer, vibes, data logging, app focus, compass, and dictation."
                        , "Games — basic, Tiny Bird, jump'n run, and 2048 starters."
                        ]
                    , paragraph "Create a project in the IDE, choose a template, then adjust Elm in watch/, protocol/, and phone/ as needed."
                    ]
                , sectionBlock "Learn the watchface loop"
                    [ paragraph "If you are new to Elm, read the guided walkthrough of the Watchface tutorial complete template. It explains model, messages, update, protocol types, the companion worker, subscriptions, view, and PebblePlatform.watchface."
                    , Route.Tutorial__WatchfaceTutorialComplete
                        |> Route.link
                            [ classes
                                [ Tw.mt s4
                                , Tw.inline_flex
                                , Tw.font_semibold
                                , Tw.text_color (blue s600)
                                , dark [ Tw.text_color (blue s400) ]
                                ]
                            ]
                            [ text "Read the watchface tutorial" ]
                    ]
                , sectionBlock "Browse package docs"
                    [ paragraph "Watch code uses elm-pebble/elm-watch. Companion bridge code uses elm-pebble/companion-core and elm-pebble/companion-preferences. Regular Elm packages such as elm/http belong on the phone side when the stock Elm compiler supports them."
                    , Route.Packages
                        |> Route.link
                            [ classes
                                [ Tw.mt s4
                                , Tw.inline_flex
                                , Tw.font_semibold
                                , Tw.text_color (blue s600)
                                , dark [ Tw.text_color (blue s400) ]
                                ]
                            ]
                            [ text "Browse Elm Pebble package docs" ]
                    ]
                , sectionBlock "Run the IDE locally (optional)"
                    [ paragraph "You can also run the IDE yourself with Docker. From the repository root:"
                    , codeBlock "docker compose up -d"
                    , paragraph "That starts the IDE on http://localhost:4000/projects with persistent volumes for projects, settings, and the Pebble SDK. See the repository README for PostgreSQL, external disk paths, WASM emulator runtime builds, and SDK version pins."
                    , externalLink "https://github.com/synalysis/elm-pebble" "elm-pebble on GitHub"
                    ]
                , sectionBlock "How the IDE is built"
                    [ paragraph "For architecture notes on Phoenix, LiveView, CodeMirror, elmc, the debugger, and MCP/ACP integration, see the IDE overview page."
                    , Route.Ide
                        |> Route.link
                            [ classes
                                [ Tw.mt s4
                                , Tw.inline_flex
                                , Tw.font_semibold
                                , Tw.text_color (blue s600)
                                , dark [ Tw.text_color (blue s400) ]
                                ]
                            ]
                            [ text "How the elm-pebble IDE is built" ]
                    ]
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
            [ text "Start here" ]
        , h1
            [ classes
                [ Tw.mt s6
                , Tw.text_n3xl
                , Tw.font_black
                , Tw.tracking_tight
                , md [ Tw.text_n4xl ]
                ]
            ]
            [ text "Getting started with Elm Pebble" ]
        , p
            [ classes
                [ Tw.mt s5
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "Create a Pebble project in the browser, learn the Elm loop on a finished watchface template, and use the docs when you need API details." ]
        ]


sectionBlock : String -> List (Html msg) -> Html msg
sectionBlock heading children =
    section
        [ classes [ Tw.mt s12 ] ]
        (h2 [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ] [ text heading ]
            :: children
        )


paragraph : String -> Html msg
paragraph value =
    p
        [ classes
            [ Tw.mt s4
            , Tw.text_color (gray s700)
            , dark [ Tw.text_color (gray s300) ]
            ]
        ]
        [ text value ]


bulletList : List String -> Html msg
bulletList items =
    ul
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
        (List.map (\item -> li [] [ text item ]) items)


codeBlock : String -> Html msg
codeBlock value =
    pre
        [ classes
            [ Tw.mt s5
            , Tw.overflow_x_auto
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_color (slate s900)
            , Tw.p s5
            , Tw.text_sm
            , Tw.text_simple white
            , dark [ Tw.border_color (slate s700) ]
            ]
        ]
        [ text value ]


externalButton : String -> String -> Html msg
externalButton url label =
    a
        [ href url
        , rel "noreferrer"
        , target "_blank"
        , classes
            [ Tw.mt s5
            , Tw.inline_flex
            , Tw.rounded_lg
            , Tw.bg_color (blue s600)
            , Tw.px s6
            , Tw.py s3
            , Tw.font_semibold
            , Tw.text_simple white
            , Tw.shadow_lg
            , Tw.raw "hover:bg-blue-700"
            ]
        ]
        [ text label ]


externalLink : String -> String -> Html msg
externalLink url label =
    a
        [ href url
        , rel "noreferrer"
        , target "_blank"
        , classes
            [ Tw.mt s4
            , Tw.inline_flex
            , Tw.font_semibold
            , Tw.text_color (blue s600)
            , dark [ Tw.text_color (blue s400) ]
            ]
        ]
        [ text label ]


backLink : Html msg
backLink =
    section
        [ classes [ Tw.mt s12 ] ]
        [ p
            [ classes [ Tw.text_color (gray s600), dark [ Tw.text_color (gray s400) ] ] ]
            [ Route.Index
                |> Route.link
                    [ classes
                        [ Tw.font_semibold
                        , Tw.text_color (blue s600)
                        , dark [ Tw.text_color (blue s400) ]
                        ]
                    ]
                    [ text "Back to the home page" ]
            ]
        ]
