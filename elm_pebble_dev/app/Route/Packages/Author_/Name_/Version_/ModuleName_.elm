module Route.Packages.Author_.Name_.Version_.ModuleName_ exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html exposing (Html, a, aside, div, h2, li, p, section, text, ul)
import Html.Attributes exposing (class, href)
import PackageDocs exposing (ModuleDoc, PackageData, PackageRoute)
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
    , moduleName : String
    }


type alias Data =
    { package : PackageData
    , moduleDoc : ModuleDoc
    }


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
        |> BackendTask.andThen
            (\routes ->
                routes
                    |> List.map
                        (\packageRoute ->
                            PackageDocs.docsFile packageRoute
                                |> BackendTask.map
                                    (List.map
                                        (\moduleDoc ->
                                            { author = packageRoute.author
                                            , name = packageRoute.name
                                            , version = PackageDocs.versionSlug packageRoute.version
                                            , moduleName = PackageDocs.moduleSlug moduleDoc.name
                                            }
                                        )
                                    )
                        )
                    |> BackendTask.combine
                    |> BackendTask.map List.concat
            )


data : RouteParams -> BackendTask FatalError Data
data routeParams =
    let
        packageRoute =
            routeFromParams routeParams
    in
    PackageDocs.packageData packageRoute
        |> BackendTask.andThen
            (\package ->
                case List.filter (.name >> (==) (PackageDocs.moduleNameFromSlug routeParams.moduleName)) package.modules of
                    moduleDoc :: _ ->
                        BackendTask.succeed { package = package, moduleDoc = moduleDoc }

                    [] ->
                        BackendTask.fail
                            (FatalError.fromString
                                ("Module "
                                    ++ routeParams.moduleName
                                    ++ " was not found in "
                                    ++ package.elmJson.name
                                )
                            )
            )


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Elm Pebble"
        , image =
            { url = [ "images", "icon-png.png" ] |> UrlPath.join |> Pages.Url.fromPath
            , alt = app.data.moduleDoc.name ++ " module documentation"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = app.data.package.elmJson.name ++ " module documentation for " ++ app.data.moduleDoc.name
        , locale = Nothing
        , title = app.data.moduleDoc.name ++ " - " ++ app.data.package.elmJson.name
        }
        |> Seo.website


view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view app _ =
    let
        package =
            app.data.package

        moduleDoc =
            app.data.moduleDoc
    in
    { title = moduleDoc.name ++ " - " ++ package.elmJson.name
    , body =
        [ DocsView.packageShell
            [ DocsView.breadcrumb
                [ ( "Home", "/" )
                , ( "Packages", "/packages" )
                , ( package.elmJson.name, PackageDocs.packageUrl package.route )
                , ( moduleDoc.name, PackageDocs.moduleUrl package.route moduleDoc.name )
                ]
            , div [ class "grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,1fr)_18rem]" ]
                [ DocsView.moduleDocs moduleDoc
                , moduleSidebar package moduleDoc
                ]
            ]
        ]
    }


moduleSidebar : PackageData -> ModuleDoc -> Html msg
moduleSidebar package moduleDoc =
    aside [ class "h-fit rounded-2xl border border-gray-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900 lg:sticky lg:top-24" ]
        [ h2 [ class "text-lg font-bold" ] [ text "Module" ]
        , p [ class "mt-2 font-mono text-sm text-gray-700 dark:text-gray-300" ] [ text moduleDoc.name ]
        , a
            [ href (PackageDocs.packageUrl package.route)
            , class "mt-4 inline-flex text-sm font-semibold text-blue-700 hover:text-blue-900 dark:text-blue-300 dark:hover:text-blue-200"
            ]
            [ text ("Back to " ++ package.elmJson.name) ]
        , h2 [ class "mt-8 text-lg font-bold" ] [ text "Declarations" ]
        , ul [ class "mt-3 space-y-2 text-sm" ]
            (List.concat
                [ List.map declarationLink moduleDoc.unions
                , List.map declarationLink moduleDoc.aliases
                , List.map declarationLink moduleDoc.values
                ]
            )
        ]


declarationLink : { a | name : String } -> Html msg
declarationLink declaration =
    li []
        [ a
            [ href ("#" ++ declaration.name)
            , class "font-mono text-blue-700 hover:text-blue-900 dark:text-blue-300 dark:hover:text-blue-200"
            ]
            [ text declaration.name ]
        ]


routeFromParams : RouteParams -> PackageRoute
routeFromParams params =
    { author = params.author
    , name = params.name
    , version = PackageDocs.versionFromSlug params.version
    }
