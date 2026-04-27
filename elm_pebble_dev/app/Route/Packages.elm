module Route.Packages exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, a, div, h1, h2, li, p, section, text, ul)
import Html.Attributes exposing (class, href, rel, target)
import PackageDocs exposing (PackageData)
import PackageDocs.View as DocsView
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import UrlPath
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    { packages : List PackageData
    }


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
    BackendTask.map Data PackageDocs.packageListData


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Elm Pebble"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = "Elm Pebble package documentation"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "Reference documentation for Elm Pebble packages and modules."
        , locale = Nothing
        , title = "Elm Pebble Package Docs"
        }
        |> Seo.website


view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view app _ =
    { title = "Elm Pebble Package Docs"
    , body =
        [ DocsView.packageShell
            [ DocsView.breadcrumb [ ( "Home", "/" ), ( "Packages", "/packages" ) ]
            , section
                [ class "rounded-2xl border border-gray-200 bg-white p-8 shadow-lg dark:border-slate-800 dark:bg-slate-900" ]
                [ h1 [ class "text-4xl font-black tracking-tight md:text-5xl" ]
                    [ text "Elm Pebble packages" ]
                , p [ class "mt-5 max-w-3xl text-lg text-gray-700 dark:text-gray-300" ]
                    [ text "Browse the generated package documentation for Pebble runtime bindings and companion bridge APIs. The structure mirrors Elm’s official package viewer, backed by docs.json and elm.json files generated from the source packages." ]
                , packageRegistryLinks
                ]
            , packageGuidance
            , div [ class "mt-8 grid grid-cols-1 gap-5 md:grid-cols-2" ]
                (List.map DocsView.packageCard app.data.packages)
            ]
        ]
    }


packageRegistryLinks : Html msg
packageRegistryLinks =
    p [ class "mt-5 max-w-3xl text-sm text-gray-600 dark:text-gray-400" ]
        [ text "For regular Elm packages, use "
        , a
            [ href "https://package.elm-lang.org/"
            , target "_blank"
            , rel "noreferrer"
            , class "font-semibold text-blue-700 underline decoration-blue-300 underline-offset-4 dark:hidden"
            ]
            [ text "package.elm-lang.org" ]
        , a
            [ href "https://dark.elm.dmy.fr/"
            , target "_blank"
            , rel "noreferrer"
            , class "hidden font-semibold text-blue-300 underline decoration-blue-500 underline-offset-4 dark:inline"
            ]
            [ text "dark.elm.dmy.fr" ]
        , text ". The dark-mode link points at the dark package viewer mirror."
        ]


packageGuidance : Html msg
packageGuidance =
    section
        [ class "mt-8 grid grid-cols-1 gap-5 md:grid-cols-2" ]
        [ div [ class "rounded-2xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900" ]
            [ h2 [ class "text-xl font-bold text-slate-900 dark:text-white" ]
                [ text "Use regular Elm packages" ]
            , p [ class "mt-3 text-sm leading-6 text-gray-700 dark:text-gray-300" ]
                [ text "Elm Pebble projects are still Elm projects. Watch and phone code can use ordinary Elm packages when those packages fit the target. Companion apps run through the normal Elm compiler, so packages such as elm/http are the right choice there." ]
            ]
        , div [ class "rounded-2xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900" ]
            [ h2 [ class "text-xl font-bold text-slate-900 dark:text-white" ]
                [ text "Watch package limits" ]
            , p [ class "mt-3 text-sm leading-6 text-gray-700 dark:text-gray-300" ]
                [ text "The watch compiler targets Pebble C, not a browser or network runtime. Packages that depend on browser-only or DOM/HTTP/file APIs cannot be used on the watch." ]
            , ul [ class "mt-3 list-disc space-y-1 pl-5 text-sm text-gray-700 dark:text-gray-300" ]
                [ li [] [ text "Avoid packages that depend on elm/browser, elm/html, elm/virtual-dom, elm/http, elm/file, or elm/bytes in watch code." ]
                , li [] [ text "Use those packages in the companion phone app when the original Elm compiler supports them." ]
                , li [] [ text "Use Elm Pebble packages for watch runtime features such as UI drawing, buttons, time, storage, vibration, and system state." ]
                ]
            ]
        ]
