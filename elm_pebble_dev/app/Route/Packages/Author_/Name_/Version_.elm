module Route.Packages.Author_.Name_.Version_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, aside, code, div, h1, h2, li, p, pre, section, span, text, ul)
import Html.Attributes exposing (class, href)
import PackageDocs exposing (PackageData, PackageRoute)
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
    { author : String
    , name : String
    , version : String
    }


type alias Data =
    PackageData


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    PackageDocs.packageRoutes
        |> BackendTask.map
            (List.map
                (\routeParams ->
                    { author = routeParams.author
                    , name = routeParams.name
                    , version = PackageDocs.versionSlug routeParams.version
                    }
                )
            )


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    PackageDocs.packageData (routeFromParams routeParams)


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Elm Pebble"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = app.data.elmJson.name ++ " package documentation"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = app.data.elmJson.summary
        , locale = Nothing
        , title = app.data.elmJson.name ++ " " ++ app.data.elmJson.version
        }
        |> Seo.website


view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view app _ =
    let
        package =
            app.data
    in
    { title = package.elmJson.name ++ " " ++ package.elmJson.version
    , body =
        [ DocsView.packageShell
            [ DocsView.breadcrumb
                [ ( "Home", "/" )
                , ( "Packages", "/packages" )
                , ( package.elmJson.name, PackageDocs.packageUrl package.route )
                ]
            , packageHero package
            , div [ class "mt-8 grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_18rem]" ]
                [ section []
                    [ h2 [ class "text-2xl font-bold tracking-tight" ] [ text "Modules" ]
                    , div [ class "mt-5 grid grid-cols-1 gap-4 md:grid-cols-2" ]
                        (List.map (DocsView.moduleCard package.route) package.modules)
                    ]
                , packageSidebar package
                ]
            ]
        ]
    }


packageHero : PackageData -> Html msg
packageHero package =
    section [ class "rounded-2xl border border-gray-200 bg-white p-8 shadow-lg dark:border-slate-800 dark:bg-slate-900" ]
        [ span [ class "rounded-md bg-blue-100 px-3 py-1 text-sm font-semibold text-blue-800 dark:bg-blue-950 dark:text-blue-200" ]
            [ text ("v" ++ package.elmJson.version) ]
        , h1 [ class "mt-5 font-mono text-4xl font-black tracking-tight md:text-5xl" ]
            [ text package.elmJson.name ]
        , p [ class "mt-5 max-w-3xl text-lg text-gray-700 dark:text-gray-300" ]
            [ text package.elmJson.summary ]
        , div [ class "mt-6 flex flex-wrap gap-3 text-sm text-gray-600 dark:text-gray-400" ]
            [ span [] [ text ("License: " ++ package.elmJson.license) ]
            , span [] [ text ("Elm: " ++ package.elmJson.elmVersion) ]
            , span [] [ text (String.fromInt (List.length package.modules) ++ " modules") ]
            ]
        ]


packageSidebar : PackageData -> Html msg
packageSidebar package =
    aside [ class "rounded-2xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900" ]
        [ h2 [ class "text-lg font-bold" ] [ text "Package Files" ]
        , ul [ class "mt-4 space-y-2 text-sm" ]
            [ li [] [ rawJsonLink (PackageDocs.elmJsonPath package.route) "elm.json" ]
            , li [] [ rawJsonLink (PackageDocs.docsPath package.route) "docs.json" ]
            ]
        , h2 [ class "mt-8 text-lg font-bold" ] [ text "Dependencies" ]
        , if List.isEmpty package.elmJson.dependencies then
            p [ class "mt-3 text-sm text-gray-600 dark:text-gray-400" ] [ text "No package dependencies." ]

          else
            ul [ class "mt-3 space-y-2 text-sm" ]
                (List.map dependencyItem package.elmJson.dependencies)
        ]


rawJsonLink : String -> String -> Html msg
rawJsonLink publicPath label =
    Html.a
        [ href (String.replace "public/" "/" publicPath)
        , class "font-mono text-blue-700 hover:text-blue-900 dark:text-blue-300 dark:hover:text-blue-200"
        ]
        [ text label ]


dependencyItem : ( String, String ) -> Html msg
dependencyItem ( package, constraint ) =
    li []
        [ pre [ class "overflow-x-auto rounded-lg bg-slate-950 p-3 text-xs text-slate-100" ]
            [ code [] [ text (package ++ " " ++ constraint) ] ]
        ]


routeFromParams : RouteParams -> PackageRoute
routeFromParams params =
    { author = params.author
    , name = params.name
    , version = PackageDocs.versionFromSlug params.version
    }
