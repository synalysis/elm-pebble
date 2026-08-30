module Route.Wasm exposing (ActionData, Data, Model, Msg(..), route)

{-| Explains the elmc WASM web compile path and hosts a WebGL demo via elm-3d-scene.
-}

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import HeroScene
import Html exposing (Html, a, code, div, h1, h2, h3, li, p, pre, section, span, text, ul)
import Html.Attributes exposing (href, rel, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, emerald, gray, s10, s100, s12, s16, s2, s200, s3, s300, s4, s400, s5, s6, s600, s700, s8, s800, s900, s950, slate, white)
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { scene : HeroScene.Model
    }


type Msg
    = SceneMsg HeroScene.Msg


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
    ( { scene = HeroScene.init }
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
        SceneMsg sceneMsg ->
            ( { model | scene = HeroScene.update sceneMsg model.scene }
            , Effect.none
            )


subscriptions :
    RouteParams
    -> UrlPath
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions _ _ _ model =
    Sub.map SceneMsg (HeroScene.subscriptions model.scene)


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
        , description = "elmc compiles Elm to WebAssembly for the browser: Browser apps, Html/Svg, Http, Time, Task, WebGL/Scene3d, and elm-pages route bytes — plus a live demo."
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
                , liveDemo model
                , pipeline
                , supportedSurface
                , howToBuild
                , parityNote
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
        [ div
            [ classes
                [ Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s8
                , Tw.items_start
                , md [ Tw.grid_cols_2 ]
                ]
            ]
            [ div []
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
                    [ text "elmc lowers the same Elm sources this site uses for elm-pages into a WASM module and a thin JS host. Browser programs boot, update, and render in the host — without shipping Pebble draw/cmd/sub specials into the web graph."
                    ]
                ]
            , asideCard
            ]
        ]


asideCard : Html msg
asideCard =
    div
        [ classes
            [ Tw.rounded_xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_color (gray s100)
            , Tw.p s6
            , dark
                [ Tw.border_color (slate s700)
                , Tw.bg_color (slate s800)
                ]
            ]
        ]
        [ h2
            [ classes [ Tw.text_lg, Tw.font_semibold ] ]
            [ text "At a glance" ]
        , ul
            [ classes
                [ Tw.mt s4
                , Tw.flex
                , Tw.flex_col
                , Tw.gap s3
                , Tw.text_base
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ glanceItem "Compiles" "IR → plan → WASM + minified host"
            , glanceItem "Runs" "Browser.* apps, Html/Svg, Http, Time, Task, ports"
            , glanceItem "This site" "npm run serve:wasm boots the SPA shell"
            , glanceItem "Demo below" "elm-3d-scene / WebGL on the WASM path"
            ]
        ]


glanceItem : String -> String -> Html msg
glanceItem label body =
    li
        [ classes [ Tw.list_none, Tw.flex, Tw.gap s3 ] ]
        [ span
            [ classes
                [ Tw.shrink_0
                , Tw.font_semibold
                , Tw.text_color (emerald s700)
                , dark [ Tw.text_color (emerald s200) ]
                , Tw.raw "min-w-[5.5rem]"
                ]
            ]
            [ text label ]
        , span [] [ text body ]
        ]


liveDemo : Model -> Html (PagesMsg Msg)
liveDemo model =
    section
        [ classes [ Tw.mt s12 ] ]
        [ div
            [ classes
                [ Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s6
                , Tw.items_end
                , md [ Tw.grid_cols_2 ]
                ]
            ]
            [ div []
                [ h2
                    [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
                    [ text "Live demo" ]
                , p
                    [ classes
                        [ Tw.mt s4
                        , Tw.text_lg
                        , Tw.text_color (gray s700)
                        , dark [ Tw.text_color (gray s300) ]
                        ]
                    ]
                    [ text "A Pebble-like watch with the Elm tangram (square) on the dial and orbiting logo-colored spheres — rendered with "
                    , codeLink "https://package.elm-lang.org/packages/ianmackenzie/elm-3d-scene/latest/" "ianmackenzie/elm-3d-scene"
                    , text " over "
                    , codeLink "https://package.elm-lang.org/packages/elm-explorations/webgl/latest/" "elm-explorations/webgl"
                    , text "."
                    ]
                ]
            , p
                [ classes
                    [ Tw.text_base
                    , Tw.text_color (gray s600)
                    , dark [ Tw.text_color (gray s400) ]
                    ]
                ]
                [ text "No physics solver: procedural orbits on "
                , codeInline "Time.every 64"
                , text " (~16 Hz) so the rest of the page stays responsive. The same scene is gated on the WASM host with "
                , codeInline "npm run verify:wasm:hero"
                , text "."
                ]
            ]
        , div
            [ classes [ Tw.mt s6, Tw.w_full ] ]
            [ Html.map (PagesMsg.fromMsg << SceneMsg) (HeroScene.view model.scene) ]
        ]


pipeline : Html msg
pipeline =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "What the WASM build is" ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.raw "max-w-3xl"
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "Reachable package code is compiled into the module; unused code can be stripped. There is no separate “port package X to WASM” step — only what the app graph needs. BackendTask route data is evaluated at compile time in Elixir; the browser loads the WASM client plus the thin host."
            ]
        , ul
            [ classes
                [ Tw.mt s6
                , Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s4
                , md [ Tw.grid_cols_2 ]
                ]
            ]
            [ bullet "Official site build"
                "npm run build → elm-pages + official Elm → JS in dist/."
            , bullet "WASM parity build"
                "npm run build:wasm → elmc --target wasm --web → dist/wasm-web/ (app.wasm, host/boot.js, manifest)."
            , bullet "Strict web apps"
                "Browser.* / elm/*-only apps keep wasm_strict: true so Pebble specials never enter the web dispatcher."
            , bullet "This elm-pages site"
                "Builds with wasm_strict: true. Missing-callee stubs and unsupported skips fail the compile; leftover Pebble ops trap instead of no-op."
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
                , Tw.raw "max-w-3xl"
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "The WASM web surface boots real Browser programs end-to-end: init/update/view, subscriptions, cmds, and page data for this elm-pages site. Pebble UI, Cmd, and Events stay out of the web graph."
            ]
        , ul
            [ classes
                [ Tw.mt s6
                , Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s4
                , md [ Tw.grid_cols_3 ]
                ]
            ]
            [ capability "Browser programs"
                "sandbox, element, document, application, and Platform.worker."
            , capability "Virtual DOM"
                "Html, Svg, Keyed, Lazy, Html.map, and event handlers."
            , capability "Browser APIs"
                "Events, Navigation, Dom.focus / viewport / setTitle."
            , capability "Effects"
                "Task, Process.sleep, Time.now / every / here, Random, Regex."
            , capability "Http & files"
                "Http expect/bytes/timeout errors; File.Download / Select; BackendTask.Http via fetch."
            , capability "Data & decode"
                "Bytes, Json.Decode/Encode (structured errors), Parser, Dict/Set equality."
            , capability "elm-pages"
                "Multi-route bytes on boot and navigation; incoming/outgoing ports with Sub.map / Cmd.map."
            , capability "WebGL / Scene3d"
                "Host webgl_* bridges; this page’s HeroScene draws on the WASM path."
            , capability "Not in web"
                "Pebble UI, Cmd, and Events — filtered from the web dispatcher."
            ]
        ]


howToBuild : Html msg
howToBuild =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n3xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text "How to build it" ]
        , div
            [ classes
                [ Tw.mt s6
                , Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s6
                , Tw.items_start
                , md [ Tw.grid_cols_2 ]
                ]
            ]
            [ div []
                [ p
                    [ classes
                        [ Tw.text_color (gray s700)
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
npm run verify:wasm:hero
npm run serve:wasm

# equivalent
./scripts/build-elm-pebble-dev-wasm.sh
elmc compile elm_pebble_dev \\
  --out-dir dist/wasm-web \\
  --target wasm --web"""
                    ]
                ]
            , div
                [ classes
                    [ Tw.rounded_xl
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
                [ h3 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text "Artifacts" ]
                , p
                    [ classes
                        [ Tw.mt s3
                        , Tw.text_base
                        , Tw.text_color (gray s700)
                        , dark [ Tw.text_color (gray s300) ]
                        ]
                    ]
                    [ text "Under "
                    , codeInline "dist/wasm-web/"
                    , text ":"
                    ]
                , ul
                    [ classes
                        [ Tw.mt s4
                        , Tw.flex
                        , Tw.flex_col
                        , Tw.gap s2
                        , Tw.text_base
                        , Tw.text_color (gray s700)
                        , dark [ Tw.text_color (gray s300) ]
                        ]
                    ]
                    [ li [ classes [ Tw.list_none ] ] [ codeInline "wasm/app.wasm", text " (+ optional .br)" ]
                    , li [ classes [ Tw.list_none ] ] [ codeInline "host/boot.js", text " (bundled host)" ]
                    , li [ classes [ Tw.list_none ] ] [ codeInline "host/browser.html" ]
                    , li [ classes [ Tw.list_none ] ] [ codeInline "elmc_wasm.manifest.json" ]
                    ]
                , p
                    [ classes
                        [ Tw.mt s5
                        , Tw.text_base
                        , Tw.text_color (gray s600)
                        , dark [ Tw.text_color (gray s400) ]
                        ]
                    ]
                    [ text "Full matrix and boot notes: "
                    , codeInline "elmc/docs/WASM_WEB_BUILD.md"
                    , text "."
                    ]
                ]
            ]
        ]


parityNote : Html msg
parityNote =
    section
        [ classes [ Tw.mt s12 ] ]
        [ div
            [ classes
                [ Tw.rounded_n2xl
                , Tw.border
                , Tw.border_color (gray s200)
                , Tw.bg_simple white
                , Tw.p s8
                , Tw.shadow_sm
                , dark
                    [ Tw.border_color (slate s800)
                    , Tw.bg_color (slate s900)
                    ]
                ]
            ]
            [ div
                [ classes
                    [ Tw.grid
                    , Tw.grid_cols_1
                    , Tw.gap s6
                    , md [ Tw.grid_cols_2 ]
                    ]
                ]
                [ div []
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "WASM parity" ]
                    , p
                        [ classes
                            [ Tw.mt s4
                            , Tw.text_color (gray s700)
                            , dark [ Tw.text_color (gray s300) ]
                            ]
                        ]
                        [ text "This page’s elm-pages shell boots under elmc WASM ("
                        , codeInline "npm run serve:wasm"
                        , text "). Index and multi-route page data, ports, and the HeroScene WebGL path are covered by "
                        , codeInline "verify:wasm"
                        , text " / "
                        , codeInline "verify:wasm:hero"
                        , text " (and optional Playwright "
                        , codeInline "verify:wasm:browser"
                        , text ")."
                        ]
                    ]
                , div []
                    [ h2
                        [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
                        [ text "Still in motion" ]
                    , p
                        [ classes
                            [ Tw.mt s4
                            , Tw.text_color (gray s700)
                            , dark [ Tw.text_color (gray s300) ]
                            ]
                        ]
                        [ text "RC ownership and Scene3d/WebGL coverage keep widening beyond this demo’s Lambertian meshes. The demo itself stays light on purpose — procedural orbits instead of elm-physics — so docs stay snappy while the toolchain catches up."
                        ]
                    ]
                ]
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
        [ h3 [ classes [ Tw.text_lg, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes [ Tw.mt s2, Tw.text_base, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
            [ text body ]
        ]


capability : String -> String -> Html msg
capability title body =
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
        [ h3 [ classes [ Tw.text_base, Tw.font_semibold ] ] [ text title ]
        , p
            [ classes [ Tw.mt s2, Tw.text_sm, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
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
