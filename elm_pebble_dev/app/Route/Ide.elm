module Route.Ide exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (div, h1, h2, img, li, p, section, span, text, ul)
import Html.Attributes exposing (alt, src)
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
            , alt = "Elm Pebble IDE"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "The elm-pebble IDE is a Phoenix LiveView app in Elixir with CodeMirror editing, debugger support, Pebble SDK builds, companion-app compilation, and MCP/ACP integration for AI tools."
        , locale = Nothing
        , title = "How the elm-pebble IDE is built"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "How the elm-pebble IDE is built"
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
                [ section
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
                        [ text "Under the hood" ]
                    , h1
                        [ classes
                            [ Tw.mt s6
                            , Tw.text_n3xl
                            , Tw.font_black
                            , Tw.tracking_tight
                            , md [ Tw.text_n4xl ]
                            ]
                        ]
                        [ text "How the elm-pebble IDE is built" ]
                    , p
                        [ classes
                            [ Tw.mt s5
                            , Tw.text_lg
                            , Tw.text_color (gray s700)
                            , dark [ Tw.text_color (gray s300) ]
                            ]
                        ]
                        [ text "The IDE is a normal Elixir application: Phoenix on the server, LiveView for the workspace UI, and the usual Mix project layout. It ties together editing, syntax-aware Elm tooling, debugger state, Pebble SDK commands, and AI-facing integration servers without turning project files into ad-hoc strings." ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Elixir, Phoenix, LiveView" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "Sessions, projects, and the editor shell run on the BEAM. LiveView pushes UI updates to your browser while the server keeps project state, runs toolchains, and talks to whatever build or debugger hooks you have wired up." ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "CodeMirror editor" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "The source editor is CodeMirror embedded in LiveView. It keeps the browser editing experience fast while the server owns project state, file persistence, formatting requests, completion context, and compiler diagnostics." ]
                    , themedScreenshot
                        { lightSrc = "/images/light-editor.png"
                        , darkSrc = "/images/dark-editor.png"
                        , altText = "Elm Pebble IDE editor with Elm source open"
                        }
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
                        [ li [] [ text "Syntax-aware highlighting and token classification for Elm source, backed by the IDE’s Elm tokenizer pipeline." ]
                        , li [] [ text "Auto-complete and hover information through the editor/LSP bridge, with a fallback completion panel when the local server path is used." ]
                        , li [] [ text "Diagnostics in the gutter, code folding, search keybindings, document formatting, indentation support, active-line highlighting, dark/light themes, and optional Vim mode." ]
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Generated lexers and parsers (Erlang on the BEAM)" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "The monorepo’s elm_ex package ships leex (`.xrl`) and yecc (`.yrl`) grammars that compile to Erlang lexer and parser modules on the BEAM—`:elm_ex_elm_lexer`, `:elm_ex_elm_parser`, and friends. They drive a faithful token stream and structured passes over Elm source." ]
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
                        [ li [] [ text "Lexer output feeds syntax-aware classification in the editor (keywords, literals, layout, and compiler mode when you want it)." ]
                        , li [] [ text "Parser-backed metadata captures module headers, imports, and related surface structure so tooling shares one contract instead of hand-rolled regex." ]
                        , li [] [ text "The same pipeline hands structured information to the formatter’s semantics stages—normalize, layout, finalize—so “format document” is grounded in what the parser actually saw." ]
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Compiler and toolchain path" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "The watch side uses elmc—the Elm-to-C compiler in the same repo—for the Pebble-shaped workflow: typecheck and extract IR, generate C and Pebble shims, and keep the editor honest about what the compiler can consume. After that, the original Pebble SDK/toolchain is still the thing that builds, packages, installs, and runs the native Pebble app." ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "The companion app takes a different path. It is compiled with the original Elm compiler to JavaScript, because it runs on the phone/browser side where the extreme watch-size constraints do not apply. That lets the watch stay small and native while the companion can use regular Elm output." ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Debugger" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "The IDE includes a lightweight debugger surface for the watch, companion, and phone runtimes. It tracks runtime models, view previews, compiler events, protocol messages, and subscription-style triggers in a timeline so you can inspect how a project changes over time." ]
                    , themedScreenshot
                        { lightSrc = "/images/light-debugger.png"
                        , darkSrc = "/images/dark-debugger.png"
                        , altText = "Elm Pebble IDE debugger showing timeline, model state, and watch preview"
                        }
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
                        [ li [] [ text "Start a debugger session from the workspace and see watch, companion, and phone state in one place." ]
                        , li [] [ text "Fire supported events such as ticks, launch events, button-like triggers, and protocol messages without rebuilding the whole mental model by hand." ]
                        , li [] [ text "Step through the event timeline, compare snapshots, replay recent messages, and inspect compiler/build events alongside runtime state." ]
                        ]
                    ]
                , section
                    [ classes [ Tw.mt s12 ] ]
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "AI integration through MCP and ACP" ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "The IDE can expose project context and controlled actions to AI tools through MCP and ACP integration surfaces. It supports a remote MCP HTTP endpoint, local stdio-style MCP configurations for clients such as Cursor or Claude Desktop, and a local ACP agent bridge for editors that speak ACP." ]
                    , p
                        [ classes [ Tw.mt s4, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "Access is capability-scoped: read, edit, and build permissions can be configured separately. That lets an AI assistant inspect project structure, edit files, or run IDE build/compiler actions according to the access you explicitly enable." ]
                    ]
                , section
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
                ]
            ]
        ]
    }


themedScreenshot :
    { lightSrc : String
    , darkSrc : String
    , altText : String
    }
    -> Html.Html msg
themedScreenshot screenshot =
    div
        [ classes
            [ Tw.mt s6
            , Tw.overflow_hidden
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.shadow_lg
            , dark [ Tw.border_color (slate s800) ]
            ]
        ]
        [ img
            [ src screenshot.lightSrc
            , alt screenshot.altText
            , classes [ Tw.w_full, Tw.raw "block dark:hidden" ]
            ]
            []
        , img
            [ src screenshot.darkSrc
            , alt screenshot.altText
            , classes [ Tw.w_full, Tw.raw "hidden dark:block" ]
            ]
            []
        ]
