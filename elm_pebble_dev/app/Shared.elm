module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Html exposing (Html, a, div, footer, header, main_, nav, node, p, text)
import Html.Attributes exposing (href, rel, target)
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, hover, md)
import Tailwind.Theme exposing (blue, gray, s100, s16, s2, s200, s3, s4, s400, s600, s700, s8, s800, s900, slate, white)
import UrlPath exposing (UrlPath)
import View exposing (View)


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Nothing
    }


type Msg
    = SharedMsg SharedMsg


type alias Data =
    ()


type SharedMsg
    = NoOp


type alias Model =
    {}


init :
    Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : UrlPath
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Effect Msg )
init _ _ =
    ( {}, Effect.none )


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg _ ->
            ( model, Effect.none )


subscriptions : UrlPath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : BackendTask FatalError Data
data =
    BackendTask.succeed ()


view :
    Data
    ->
        { path : UrlPath
        , route : Maybe Route
        }
    -> Model
    -> (Msg -> msg)
    -> View msg
    -> { body : List (Html msg), title : String }
view _ page _ _ pageView =
    { body =
        [ siteHeader page.route
        , main_ [] pageView.body
        , siteFooter
        ]
    , title = pageView.title
    }


siteHeader : Maybe Route -> Html msg
siteHeader currentRoute =
    let
        navItems =
            siteNavItems currentRoute
    in
    header
        [ classes
            [ Tw.sticky
            , Tw.border_b
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            , Tw.raw "top-0 z-50 backdrop-blur-sm bg-white/90 dark:bg-slate-950/90"
            ]
        ]
        [ div
            [ classes
                [ Tw.mx_auto
                , Tw.w_full
                , Tw.raw "max-w-6xl"
                , Tw.px s4
                , Tw.py s3
                , md [ Tw.px s8 ]
                ]
            ]
            [ div
                [ classes
                    [ Tw.flex
                    , Tw.w_full
                    , Tw.items_center
                    , Tw.justify_between
                    , Tw.gap s4
                    ]
                ]
                [ siteLogo
                , desktopNav navItems
                , mobileNavMenu navItems
                ]
            ]
        ]


siteLogo : Html msg
siteLogo =
    Route.link
        [ classes
            [ Tw.shrink_0
            , Tw.text_lg
            , Tw.font_semibold
            , Tw.tracking_tight
            , Tw.text_color (slate s900)
            , dark [ Tw.text_simple white ]
            , hover [ Tw.text_color (blue s600), dark [ Tw.text_color (blue s400) ] ]
            ]
        ]
        [ text "Elm Pebble" ]
        Route.Index


desktopNav : List (Html msg) -> Html msg
desktopNav items =
    nav
        [ classes
            [ Tw.raw "site-header-desktop-nav"
            , Tw.flex
            , Tw.flex_1
            , Tw.flex_wrap
            , Tw.items_center
            , Tw.justify_end
            , Tw.gap s2
            , Tw.raw "min-w-0"
            ]
        ]
        items


mobileNavMenu : List (Html msg) -> Html msg
mobileNavMenu items =
    div
        [ classes [ Tw.shrink_0, Tw.raw "site-header-mobile-menu" ] ]
        [ node "details"
            [ classes [ Tw.relative ] ]
        [ node "summary"
            [ classes
                [ Tw.rounded_md
                , Tw.border
                , Tw.border_color (gray s200)
                , Tw.px s3
                , Tw.py s2
                , Tw.text_sm
                , Tw.font_semibold
                , Tw.text_color (gray s700)
                , dark
                    [ Tw.border_color (slate s700)
                    , Tw.text_color (gray s200)
                    ]
                , Tw.raw "cursor-pointer list-none [&::-webkit-details-marker]:hidden"
                ]
            ]
            [ text "Menu" ]
        , nav
            [ classes
                [ Tw.absolute
                , Tw.mt s2
                , Tw.flex
                , Tw.flex_col
                , Tw.gap s2
                , Tw.raw "right-0 w-56 max-w-[calc(100vw-2rem)]"
                , Tw.rounded_lg
                , Tw.border
                , Tw.border_color (gray s200)
                , Tw.bg_simple white
                , Tw.p s2
                , Tw.shadow_lg
                , dark
                    [ Tw.border_color (slate s700)
                    , Tw.bg_color (slate s900)
                    ]
                , Tw.raw "z-50 [&_a]:block [&_a]:w-full"
                ]
            ]
            items
        ]
        ]


siteNavItems : Maybe Route -> List (Html msg)
siteNavItems currentRoute =
    [ navLink currentRoute Route.Index "Home"
    , navLink currentRoute Route.GettingStarted "Start"
    , navExternal "https://ide.elm-pebble.dev" "Open IDE"
    , navLink currentRoute Route.Tutorial__WatchfaceTutorialComplete "Tutorial"
    , navHref "/packages" "Docs"
    , navLink currentRoute Route.Ide "IDE"
    , navLink currentRoute Route.Articles__WhyElmForPebble "Why Elm"
    , navLink currentRoute Route.Source "Source"
    ]


navLink : Maybe Route -> Route -> String -> Html msg
navLink currentRoute target label =
    let
        active =
            currentRoute == Just target
    in
    Route.link
        [ classes
            [ Tw.text_sm
            , Tw.font_medium
            , Tw.rounded_md
            , Tw.px s3
            , Tw.py s2
            , Tw.transition_colors
            , if active then
                Tw.batch
                    [ Tw.bg_color (blue s100)
                    , Tw.text_color (blue s900)
                    , dark
                        [ Tw.bg_color (blue s900)
                        , Tw.text_color (blue s100)
                        ]
                    ]

              else
                Tw.batch
                    [ Tw.text_color (gray s700)
                    , dark [ Tw.text_color (gray s200) ]
                    , hover
                        [ Tw.bg_color (gray s100)
                        , dark [ Tw.bg_color (slate s800) ]
                        ]
                    ]
            ]
        ]
        [ text label ]
        target


navHref : String -> String -> Html msg
navHref url label =
    a
        [ href url
        , classes navItemClasses
        ]
        [ text label ]


navExternal : String -> String -> Html msg
navExternal url label =
    a
        [ href url
        , target "_blank"
        , rel "noreferrer"
        , classes navItemClasses
        ]
        [ text label ]


footerExternalLink : String -> String -> Html msg
footerExternalLink url label =
    a
        [ href url
        , target "_blank"
        , rel "noreferrer"
        , classes
            [ Tw.font_medium
            , Tw.text_color (blue s600)
            , hover [ Tw.text_color (blue s700) ]
            , dark [ Tw.text_color (blue s400) ]
            ]
        ]
        [ text label ]


navItemClasses : List Tw.Tailwind
navItemClasses =
    [ Tw.text_sm
    , Tw.font_medium
    , Tw.rounded_md
    , Tw.px s3
    , Tw.py s2
    , Tw.transition_colors
    , Tw.text_color (gray s700)
    , dark [ Tw.text_color (gray s200) ]
    , hover
        [ Tw.bg_color (gray s100)
        , dark [ Tw.bg_color (slate s800) ]
        ]
    ]


siteFooter : Html msg
siteFooter =
    footer
        [ classes
            [ Tw.border_t
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , Tw.px s4
            , Tw.py s8
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            ]
        ]
        [ div
            [ classes
                [ Tw.mx_auto
                , Tw.w_full
                , Tw.raw "max-w-6xl"
                , Tw.text_sm
                , Tw.text_color (gray s600)
                , dark [ Tw.text_color (gray s400) ]
                ]
            ]
            [ p []
                [ text "Elm Pebble is open-source tooling for the "
                , footerExternalLink "https://repebble.com/" "Pebble ecosystem"
                , text ". It is an independent project, not affiliated with Elm, the Elm Software Foundation, Core Devices, or Pebble trademark owners."
                ]
            , p
                [ classes [ Tw.mt s3 ] ]
                [ text "Developed by "
                , footerExternalLink "https://github.com/synalysis" "Synalysis"
                , text ". Site built with "
                , footerExternalLink "https://elm-pages.com/" "elm-pages"
                , text "."
                ]
            ]
        ]
