module Route.Source exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (a, div, h1, p, section, span, text)
import Html.Attributes exposing (href, rel, target)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import Tailwind as Tw exposing (classes)
import Tailwind.Breakpoints exposing (dark, md)
import Tailwind.Theme exposing (blue, gray, s10, s100, s12, s16, s2, s200, s3, s300, s5, s6, s600, s700, s8, s800, s900, s950, slate, white)
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
            , alt = "Elm Pebble source code"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Find the Elm Pebble source code on GitHub."
        , locale = Nothing
        , title = "Elm Pebble source code"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view _ _ =
    { title = "Source | Elm Pebble"
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
                        [ text "Open source" ]
                    , h1
                        [ classes
                            [ Tw.mt s6
                            , Tw.text_n3xl
                            , Tw.font_black
                            , Tw.tracking_tight
                            , md [ Tw.text_n4xl ]
                            ]
                        ]
                        [ text "Elm Pebble source code" ]
                    , p
                        [ classes [ Tw.mt s5, Tw.text_lg, Tw.text_color (gray s700), dark [ Tw.text_color (gray s300) ] ] ]
                        [ text "Elm Pebble is developed in the open. The repository contains the website, IDE, compiler, package sources, project templates, and supporting tools." ]
                    , p
                        [ classes [ Tw.mt s6 ] ]
                        [ a
                            [ href "https://github.com/synalysis/elm-pebble"
                            , target "_blank"
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
                            [ text "View elm-pebble on GitHub" ]
                        ]
                    ]
                ]
            ]
        ]
    }
