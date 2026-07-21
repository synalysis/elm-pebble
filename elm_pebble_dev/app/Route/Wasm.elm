module Route.Wasm exposing (ActionData, Data, Model, Msg(..), route)

{-| Explains the elmc WASM web compile path and hosts the Elm+Pebble physics demo.
-}

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import HeroPhysics
import Html exposing (Html, a, code, div, h1, h2, li, p, pre, section, span, text, ul)
import Html.Attributes exposing (href, rel, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, emerald, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s600, s700, s8, s800, s900, s950, s96, slate, white)
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { physics : HeroPhysics.Model
    }


type Msg
    = PhysicsMsg HeroPhysics.Msg


type alias RouteParams =
    {}


type alias Data =
    {}


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , init = init
            , update = update
            , subscriptions = subscriptions
            }


init :
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init _ _ =
    ( { physics = HeroPhysics.init }
    , Effect.none
    )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        PhysicsMsg physicsMsg ->
            ( { model | physics = HeroPhysics.update physicsMsg model.physics }
            , Effect.none
            )


subscriptions :
    RouteParams
    -> UrlPath
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions _ _ _ model =
    Sub.map PhysicsMsg (HeroPhysics.subscriptions model.physics)


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
            , alt = "Elm Pebble WASM"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "How elmc compiles Elm to WebAssembly for the browser, and what it takes for demos like elm-physics to lower cleanly."
        , locale = Nothing
        , title = "elmc WASM compile"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view _ _ model =
    { title = "WASM | Elm Pebble"
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
                [ intro
                , section
                    [ classes [ Tw.mt s10 ] ]
                    [ h2
                        [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Live demo" ]
                    , p
                        [ classes
                            [ Tw.mt s4
                            , Tw.max_w s96
                            , Tw.text_lg
                            , Tw.text_color (gray s700)
                            , dark [ Tw.text_color (gray s300) ]
                            ]
                        ]
                        [ text "Green Elm “ideas” bounce around a Pebble watch. The simulation uses "
                        , codeLink "https://package.elm-lang.org/packages/w0rm/elm-physics/6.2.0/" "w0rm/elm-physics"
                        , text "; rendering is Svg (not WebGL), so it stays on the WASM web surface once plan lowering is complete."
                        ]
                    , div
                        [ classes [ Tw.mt s6, Tw.w_full ] ]
                        [ HeroPhysics.view model.physics ]
                    ]
                , whatIsWasm
                , howToBuild
                , supportedSurface
                , physicsGap
                ]
            ]
        ]
    }


intro : Html msg
intro =
    section
        [ classes
            [ Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.px s8
            , Tw.py s10
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
            [ text "elmc target: wasm + web" ]
        , h1
            [ classes
                [ Tw.mt s6
                , Tw.text_n4xl
                , Tw.font_black
                , Tw.tracking_tight
                , md [ Tw.text_n5xl ]
                ]
            ]
            [ text "Elm → WebAssembly with elmc" ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "Beside the usual elm-pages JavaScript build, this site can be compiled by "
            , text "elmc"
            , text " into a WASM module plus a thin JS host. That path is how we prove browser parity for the same Elm sources—without shipping Pebble draw/cmd/sub specials into the web graph."
            ]
        ]


whatIsWasm : Html msg
whatIsWasm =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "What the WASM build is" ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.max_w s96
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "elmc lowers Elm IR to a plan, then emits WebAssembly. Reachable package code (including dependencies) is compiled into that module when it is used from the app entry. Dead code can be stripped. There is no separate “port package X to WASM” step—only what the graph needs."
            ]
        , ul
            [ classes [ Tw.mt s6, Tw.grid, Tw.grid_cols_1, Tw.gap s4, md [ Tw.grid_cols_2 ] ] ]
            [ bullet "Official site build"
                "npm run build → elm-pages + official Elm → JS in dist/."
            , bullet "WASM parity build"
                "npm run build:wasm → elmc --target wasm --web → dist/wasm-web/ (app.wasm, host/boot.js, manifest)."
            , bullet "Strict web apps"
                "Browser.* / elm/*-only apps use wasm_strict: true so Pebble specials never sneak into the web dispatcher."
            , bullet "This elm-pages site"
                "Uses wasm_strict: false in the build script because the combined graph still carries some Pebble-only plan ops; browser-relevant stubs are gated empty."
            ]
        ]


howToBuild : Html msg
howToBuild =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "How to build it" ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "From "
            , codeInline "elm_pebble_dev/"
            , text " or the repo root:"
            ]
        , pre
            [ classes
                [ Tw.mt s4
                , Tw.overflow_x_auto
                , Tw.rounded_lg
                , Tw.border
                , Tw.border_color (gray s200)
                , Tw.bg_color (slate s900)
                , Tw.p s4
                , Tw.text_sm
                , Tw.text_color (gray s100)
                , dark [ Tw.border_color (slate s700) ]
                ]
            ]
            [ text """npm run build:wasm
npm run verify:wasm
npm run serve:wasm

# equivalent
./scripts/build-elm-pebble-dev-wasm.sh
elmc compile elm_pebble_dev --out-dir dist/wasm-web --target wasm --web"""
            ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.text_base
                , Tw.text_color (gray s600)
                , dark [ Tw.text_color (gray s400) ]
                ]
            ]
            [ text "Artifacts land under "
            , codeInline "dist/wasm-web/"
            , text ": "
            , codeInline "wasm/app.wasm"
            , text ", "
            , codeInline "host/browser.html"
            , text ", and "
            , codeInline "elmc_wasm.manifest.json"
            , text ". Details live in "
            , codeInline "elmc/docs/WASM_WEB_BUILD.md"
            , text "."
            ]
        ]


supportedSurface : Html msg
supportedSurface =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "What already lowers" ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.max_w s96
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "The WASM web surface covers Browser programs, Html / Svg / VirtualDom, keyed/lazy nodes, Browser.Events (including animation frames), Time, Task, Http, File, Bytes, Json, Parser, Random, Regex, and elm-pages route bytes. Pebble UI/Cmd/Events stay out of the web graph."
            ]
        ]


physicsGap : Html msg
physicsGap =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "Why this demo is not in the nav yet" ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.max_w s96
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "Official Elm (elm-pages) runs the animation fine. elmc can emit a WASM module for a minimal elm-physics fixture, but about a dozen Internal/Collision helpers still hit plan-lowering gaps and become missing-callee stubs. Until "
            , codeInline "stub_functions == []"
            , text " for that probe (and the site graph), the WASM menu entry stays commented out so we do not advertise a broken parity path."
            ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.text_base
                , Tw.text_color (gray s600)
                , dark [ Tw.text_color (gray s400) ]
                ]
            ]
            [ text "Probe fixture: "
            , codeInline "elmc/test/fixtures/wasm_web_physics_hero_project/"
            , text ". Gate when ready: empty stubs + page-data / browser smoke for this route."
            ]
        ]


bullet : String -> String -> Html msg
bullet title body =
    li
        [ classes
            [ Tw.list_none
            , Tw.rounded_lg
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.p s5
            , Tw.shadow_sm
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ h2 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes [ Tw.mt s2, Tw.text_base, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text body ]
        ]


codeInline : String -> Html msg
codeInline value =
    code
        [ classes
            [ Tw.rounded_md
            , Tw.bg_color (gray s200)
            , Tw.px s2
            , Tw.py s2
            , Tw.text_sm
            , Tw.font_semibold
            , dark [ Tw.bg_color (slate s800) ]
            ]
        ]
        [ text value ]


codeLink : String -> String -> Html msg
codeLink url label =
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
