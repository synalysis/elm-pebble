module PackageDocs.View exposing
    ( breadcrumb
    , declarationCount
    , moduleCard
    , moduleDocs
    , packageCard
    , packageShell
    , renderComment
    )

import Html exposing (Html, a, code, div, h1, h2, h3, li, p, pre, section, span, text, ul)
import Html.Attributes exposing (class, href, id)
import PackageDocs exposing (AliasDoc, ElmJson, ModuleDoc, PackageData, PackageRoute, UnionDoc, ValueDoc)
import Route


packageShell : List (Html msg) -> Html msg
packageShell children =
    div
        [ class "min-h-screen bg-gray-100 text-slate-900 antialiased dark:bg-slate-950 dark:text-gray-100" ]
        [ div [ class "mx-auto w-full max-w-6xl px-6 py-12 leading-relaxed md:px-10 md:py-16" ] children ]


breadcrumb : List ( String, String ) -> Html msg
breadcrumb items =
    div [ class "mb-6 flex flex-wrap items-center gap-2 text-sm text-gray-600 dark:text-gray-400" ]
        (List.intersperse
            (span [ class "text-gray-400" ] [ text "/" ])
            (List.map breadcrumbItem items)
        )


breadcrumbItem : ( String, String ) -> Html msg
breadcrumbItem ( label, url ) =
    a [ href url, class "font-medium text-blue-700 hover:text-blue-900 dark:text-blue-300 dark:hover:text-blue-200" ]
        [ text label ]


packageCard : PackageData -> Html msg
packageCard package =
    Route.link
        [ class "block rounded-xl border border-gray-200 bg-white p-6 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md dark:border-slate-800 dark:bg-slate-900"
        ]
        [ div [ class "flex flex-wrap items-baseline justify-between gap-3" ]
            [ h2 [ class "text-xl font-bold tracking-tight text-slate-950 dark:text-white" ]
                [ text package.elmJson.name ]
            , span [ class "rounded-md bg-blue-100 px-2 py-1 text-xs font-semibold text-blue-800 dark:bg-blue-950 dark:text-blue-200" ]
                [ text package.elmJson.version ]
            ]
        , p [ class "mt-3 text-gray-700 dark:text-gray-300" ] [ text package.elmJson.summary ]
        , div [ class "mt-4 flex flex-wrap gap-2 text-sm text-gray-600 dark:text-gray-400" ]
            [ span [] [ text (String.fromInt (List.length package.modules) ++ " modules") ]
            , span [] [ text ("License: " ++ package.elmJson.license) ]
            ]
        ]
        (Route.Packages__Author___Name___Version_
            { author = package.route.author
            , name = package.route.name
            , version = PackageDocs.versionSlug package.route.version
            }
        )


moduleCard : PackageRoute -> ModuleDoc -> Html msg
moduleCard route moduleDoc =
    Route.link
        [ class "block rounded-lg border border-gray-200 bg-white p-4 transition hover:border-blue-300 hover:shadow-sm dark:border-slate-800 dark:bg-slate-900 dark:hover:border-blue-700"
        ]
        [ h3 [ class "font-mono text-base font-semibold text-blue-700 dark:text-blue-300" ] [ text moduleDoc.name ]
        , p [ class "mt-2 text-sm text-gray-600 dark:text-gray-400" ]
            [ text
                (String.fromInt (declarationCount moduleDoc)
                    ++ " documented declarations"
                )
            ]
        ]
        (Route.Packages__Author___Name___Version___ModuleName_
            { author = route.author
            , name = route.name
            , version = PackageDocs.versionSlug route.version
            , moduleName = PackageDocs.moduleSlug moduleDoc.name
            }
        )


moduleDocs : ModuleDoc -> Html msg
moduleDocs moduleDoc =
    div [ class "space-y-10" ]
        [ section [ class "rounded-2xl border border-gray-200 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900" ]
            [ h1 [ class "font-mono text-3xl font-black tracking-tight md:text-4xl" ] [ text moduleDoc.name ]
            , div [ class "mt-6 space-y-4 text-gray-700 dark:text-gray-300" ] (renderComment moduleDoc.comment)
            ]
        , declarationsSection "Union Types" (List.map unionDoc moduleDoc.unions)
        , declarationsSection "Type Aliases" (List.map aliasDoc moduleDoc.aliases)
        , declarationsSection "Values" (List.map valueDoc moduleDoc.values)
        ]


declarationsSection : String -> List (Html msg) -> Html msg
declarationsSection title children =
    if List.isEmpty children then
        text ""

    else
        section [ class "rounded-2xl border border-gray-200 bg-white p-8 shadow-sm dark:border-slate-800 dark:bg-slate-900" ]
            [ h2 [ class "text-2xl font-bold tracking-tight" ] [ text title ]
            , div [ class "mt-6 space-y-8" ] children
            ]


unionDoc : UnionDoc -> Html msg
unionDoc union =
    declarationBlock union.name
        (typeHeader ("type " ++ union.name ++ argsSuffix union.args)
            :: (case union.cases of
                    [] ->
                        []

                    cases ->
                        [ pre [ class "mt-3 overflow-x-auto rounded-lg bg-slate-950 p-4 text-sm text-slate-100" ]
                            [ code [] [ text (unionCasesSource union.name cases) ] ]
                        ]
               )
            ++ renderComment union.comment
        )


aliasDoc : AliasDoc -> Html msg
aliasDoc alias_ =
    declarationBlock alias_.name
        (typeHeader ("type alias " ++ alias_.name ++ argsSuffix alias_.args ++ " = " ++ alias_.tipe)
            :: renderComment alias_.comment
        )


valueDoc : ValueDoc -> Html msg
valueDoc value =
    declarationBlock value.name
        (typeHeader (value.name ++ " : " ++ value.tipe)
            :: renderComment value.comment
        )


declarationBlock : String -> List (Html msg) -> Html msg
declarationBlock name children =
    div [ id name, class "scroll-mt-24 border-t border-gray-200 pt-6 first:border-t-0 first:pt-0 dark:border-slate-800" ]
        (h3 [ class "font-mono text-xl font-bold text-slate-950 dark:text-white" ] [ text name ]
            :: div [ class "mt-3 space-y-4" ] children
            :: []
        )


typeHeader : String -> Html msg
typeHeader source =
    pre [ class "overflow-x-auto rounded-lg bg-slate-950 p-4 text-sm text-slate-100" ]
        [ code [] [ text source ] ]


unionCasesSource : String -> List ( String, List String ) -> String
unionCasesSource name cases =
    case cases of
        [] ->
            "type " ++ name

        first :: rest ->
            "type "
                ++ name
                ++ "\n    = "
                ++ caseSource first
                ++ (rest
                        |> List.map (\case_ -> "\n    | " ++ caseSource case_)
                        |> String.concat
                   )


caseSource : ( String, List String ) -> String
caseSource ( name, args ) =
    String.join " " (name :: args)


argsSuffix : List String -> String
argsSuffix args =
    case args of
        [] ->
            ""

        _ ->
            " " ++ String.join " " args


renderComment : String -> List (Html msg)
renderComment comment =
    comment
        |> String.split "\n"
        |> commentBlocks []
        |> List.map renderBlock


type CommentBlock
    = Paragraph (List String)
    | Heading String
    | CodeBlock (List String)


commentBlocks : List CommentBlock -> List String -> List CommentBlock
commentBlocks acc lines =
    case lines of
        [] ->
            List.reverse acc

        line :: rest ->
            let
                trimmed =
                    String.trim line
            in
            if trimmed == "" || String.startsWith "@docs" trimmed then
                commentBlocks acc rest

            else if String.startsWith "# " trimmed then
                commentBlocks (Heading (String.dropLeft 2 trimmed) :: acc) rest

            else if String.startsWith "    " line then
                let
                    ( codeLines, remaining ) =
                        takeWhile (\candidate -> String.startsWith "    " candidate || String.trim candidate == "") lines
                in
                commentBlocks (CodeBlock (List.map (String.dropLeft 4) codeLines) :: acc) remaining

            else
                let
                    ( paragraphLines, remaining ) =
                        takeWhile
                            (\candidate ->
                                let
                                    candidateTrimmed =
                                        String.trim candidate
                                in
                                candidateTrimmed
                                    /= ""
                                    && not (String.startsWith "# " candidateTrimmed)
                                    && not (String.startsWith "@docs" candidateTrimmed)
                                    && not (String.startsWith "    " candidate)
                            )
                            lines
                in
                commentBlocks (Paragraph paragraphLines :: acc) remaining


takeWhile : (a -> Bool) -> List a -> ( List a, List a )
takeWhile predicate list =
    case list of
        [] ->
            ( [], [] )

        item :: rest ->
            if predicate item then
                let
                    ( matches, remaining ) =
                        takeWhile predicate rest
                in
                ( item :: matches, remaining )

            else
                ( [], list )


renderBlock : CommentBlock -> Html msg
renderBlock block =
    case block of
        Heading title ->
            h2 [ class "pt-4 text-xl font-bold tracking-tight text-slate-950 dark:text-white" ] [ text title ]

        Paragraph lines ->
            p [ class "text-base text-gray-700 dark:text-gray-300" ] [ text (String.join " " (List.map String.trim lines)) ]

        CodeBlock lines ->
            pre [ class "overflow-x-auto rounded-lg bg-slate-950 p-4 text-sm text-slate-100" ]
                [ code [] [ text (String.join "\n" lines) ] ]


declarationCount : ModuleDoc -> Int
declarationCount moduleDoc =
    List.length moduleDoc.unions + List.length moduleDoc.aliases + List.length moduleDoc.values
