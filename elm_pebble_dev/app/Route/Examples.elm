module Route.Examples exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ExamplesCatalog exposing (Example)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, a, div, h1, h2, img, p, section, span, text)
import Html.Attributes exposing (alt, href, rel, src, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
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
            , alt = "Elm Pebble example watchfaces and games"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Browse Pebble watchfaces and games built in Elm, then open any template in the hosted IDE."
        , locale = Nothing
        , title = "Examples — watchfaces and games in Elm"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "Examples | Elm Pebble"
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
                , gallerySection "Watchfaces" (examplesIn "Watchface")
                , gallerySection "Games" (examplesIn "Game")
                , nextSteps
                ]
            ]
        ]
    }


examplesIn : String -> List Example
examplesIn category =
    List.filter (\example -> example.category == category) ExamplesCatalog.all


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
            [ text "See what you can build" ]
        , h1
            [ classes
                [ Tw.mt s6
                , Tw.text_n3xl
                , Tw.font_black
                , Tw.tracking_tight
                , md [ Tw.text_n4xl ]
                ]
            ]
            [ text "Watchfaces and games in Elm" ]
        , p
            [ classes
                [ Tw.mt s5
                , Tw.max_w s96
                , Tw.text_lg
                , Tw.text_color (gray s700)
                , dark [ Tw.text_color (gray s300) ]
                ]
            ]
            [ text "These are real project templates. Open any one in the hosted IDE, tweak the Elm, and run it in the emulator — then install on a Pebble when you are ready." ]
        , p
            [ classes
                [ Tw.mt s4
                , Tw.text_base
                , Tw.text_color (gray s600)
                , dark [ Tw.text_color (gray s400) ]
                ]
            ]
            [ text "New to Elm? Start with Digital or the tutorial watchface. Already write Elm? Jump into YES, Tangram Time, or 2048." ]
        ]


gallerySection : String -> List Example -> Html msg
gallerySection heading examples =
    section
        [ classes [ Tw.mt s12 ] ]
        [ h2
            [ classes [ Tw.text_n2xl, Tw.font_semibold, Tw.tracking_tight ] ]
            [ text heading ]
        , div
            [ classes
                [ Tw.mt s6
                , Tw.grid
                , Tw.grid_cols_1
                , Tw.gap s5
                , sm [ Tw.grid_cols_2 ]
                , md [ Tw.grid_cols_3 ]
                ]
            ]
            (List.map exampleCard examples)
        ]


exampleCard : Example -> Html msg
exampleCard example =
    div
        [ classes
            [ Tw.flex
            , Tw.flex_col
            , Tw.overflow_hidden
            , Tw.rounded_n2xl
            , Tw.border
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
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
                , Tw.items_center
                , Tw.justify_center
                , Tw.bg_color (slate s950)
                , Tw.px s6
                , Tw.py s8
                ]
            ]
            [ img
                [ src example.image
                , alt (example.title ++ " on a Pebble screen")
                , classes
                    [ Tw.raw "h-40 w-auto max-w-full"
                    , Tw.rounded_lg
                    , Tw.shadow_lg
                    ]
                ]
                []
            ]
        , div
            [ classes [ Tw.flex, Tw.flex_1, Tw.flex_col, Tw.gap s3, Tw.p s5 ] ]
            [ span
                [ classes
                    [ Tw.text_sm
                    , Tw.font_semibold
                    , Tw.raw "uppercase tracking-wide"
                    , Tw.text_color (emerald s700)
                    , dark [ Tw.text_color (emerald s300) ]
                    ]
                ]
                [ text example.category ]
            , h2
                [ classes [ Tw.text_xl, Tw.font_semibold, Tw.tracking_tight ] ]
                [ text example.title ]
            , p
                [ classes
                    [ Tw.flex_1
                    , Tw.text_base
                    , Tw.text_color (gray s700)
                    , dark [ Tw.text_color (gray s300) ]
                    ]
                ]
                [ text example.blurb ]
            , a
                [ href (ExamplesCatalog.ideTemplateUrl example.templateKey)
                , target "_blank"
                , rel "noreferrer"
                , classes
                    [ Tw.mt s2
                    , Tw.inline_flex
                    , Tw.w_fit
                    , Tw.rounded_lg
                    , Tw.bg_color (blue s600)
                    , Tw.px s4
                    , Tw.py s2
                    , Tw.text_sm
                    , Tw.font_semibold
                    , Tw.text_simple white
                    , Tw.shadow_lg
                    , Tw.raw "hover:bg-blue-700"
                    ]
                ]
                [ text "Open in IDE" ]
            ]
        ]


nextSteps : Html msg
nextSteps =
    section
        [ classes [ Tw.mt s12, Tw.flex, Tw.flex_col, Tw.gap s4 ] ]
        [ Route.GettingStarted
            |> Route.link
                [ classes
                    [ Tw.inline_flex
                    , Tw.font_semibold
                    , Tw.text_color (blue s600)
                    , hover [ Tw.text_color (blue s700) ]
                    , dark [ Tw.text_color (blue s400) ]
                    ]
                ]
                [ text "Getting started guide" ]
        , Route.Tutorial__WatchfaceTutorialComplete
            |> Route.link
                [ classes
                    [ Tw.inline_flex
                    , Tw.font_semibold
                    , Tw.text_color (blue s600)
                    , hover [ Tw.text_color (blue s700) ]
                    , dark [ Tw.text_color (blue s400) ]
                    ]
                ]
                [ text "Watchface tutorial walkthrough" ]
        , Route.Articles__WhyElmForPebble
            |> Route.link
                [ classes
                    [ Tw.inline_flex
                    , Tw.font_semibold
                    , Tw.text_color (blue s600)
                    , hover [ Tw.text_color (blue s700) ]
                    , dark [ Tw.text_color (blue s400) ]
                    ]
                ]
                [ text "Why Elm fits Pebble" ]
        ]
