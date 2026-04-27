module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Html exposing (Html, a, div, footer, header, main_, nav, text)
import Html.Attributes exposing (href)
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
    header
        [ classes
            [ Tw.sticky
            , Tw.z_50
            , Tw.border_b
            , Tw.border_color (gray s200)
            , Tw.bg_simple white
            , dark
                [ Tw.border_color (slate s800)
                , Tw.bg_color (slate s900)
                ]
            , Tw.raw "top-0 backdrop-blur-sm bg-white/90 dark:bg-slate-950/90"
            ]
        ]
        [ div
            [ classes
                [ Tw.mx_auto
                , Tw.flex
                , Tw.h s16
                , Tw.w_full
                , Tw.raw "max-w-6xl"
                , Tw.items_center
                , Tw.justify_between
                , Tw.gap s4
                , Tw.px s4
                , md [ Tw.px s8 ]
                ]
            ]
            [ Route.link
                [ classes
                    [ Tw.text_lg
                    , Tw.font_semibold
                    , Tw.tracking_tight
                    , Tw.text_color (slate s900)
                    , dark [ Tw.text_simple white ]
                    , hover [ Tw.text_color (blue s600), dark [ Tw.text_color (blue s400) ] ]
                    ]
                ]
                [ text "Elm Pebble" ]
                Route.Index
            , nav
                [ classes [ Tw.flex, Tw.items_center, Tw.gap s2, Tw.flex_wrap ] ]
                [ navLink currentRoute Route.Index "Home"
                , navLink currentRoute Route.Articles__WhyElmForPebble "Why Elm"
                , navLink currentRoute Route.Ide "IDE"
                , navHref "/packages" "Docs"
                , navLink currentRoute Route.Tutorial__WatchfaceTutorialComplete "Tutorial"
                , navLink currentRoute Route.Source "Source"
                ]
            ]
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
        , classes
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
        ]
        [ text label ]


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
            [ text "Elm Pebble is an open-source development and is not affiliated with Elm, the Elm Software Foundation, Pebble, or any Pebble trademark owners." ]
        ]
