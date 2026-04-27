module PackageDocs exposing
    ( AliasDoc
    , ElmJson
    , ModuleDoc
    , PackageData
    , PackageRoute
    , UnionDoc
    , ValueDoc
    , docsFile
    , docsPath
    , elmJsonFile
    , elmJsonPath
    , moduleNameFromSlug
    , modulePath
    , moduleSlug
    , moduleUrl
    , packageData
    , packageListData
    , packageRoutes
    , packageUrl
    , routeFromDocsPath
    , versionFromSlug
    , versionSlug
    )

import BackendTask exposing (BackendTask)
import BackendTask.File as File
import BackendTask.Glob as Glob
import Dict
import FatalError exposing (FatalError)
import Json.Decode as Decode exposing (Decoder)


type alias PackageRoute =
    { author : String
    , name : String
    , version : String
    }


type alias ElmJson =
    { name : String
    , summary : String
    , license : String
    , version : String
    , elmVersion : String
    , exposedModules : List String
    , dependencies : List ( String, String )
    }


type alias PackageData =
    { route : PackageRoute
    , elmJson : ElmJson
    , modules : List ModuleDoc
    }


type alias ModuleDoc =
    { name : String
    , comment : String
    , unions : List UnionDoc
    , aliases : List AliasDoc
    , values : List ValueDoc
    }


type alias UnionDoc =
    { name : String
    , comment : String
    , args : List String
    , cases : List ( String, List String )
    }


type alias AliasDoc =
    { name : String
    , comment : String
    , args : List String
    , tipe : String
    }


type alias ValueDoc =
    { name : String
    , comment : String
    , tipe : String
    }


packageRoutes : BackendTask FatalError (List PackageRoute)
packageRoutes =
    Glob.fromString "public/package-docs/packages/*/*/*/docs.json"
        |> BackendTask.map
            (List.filterMap routeFromDocsPath
                >> List.filter isPublishedPackageRoute
                >> List.sortBy (\route -> route.author ++ "/" ++ route.name)
            )


packageListData : BackendTask FatalError (List PackageData)
packageListData =
    packageRoutes
        |> BackendTask.andThen
            (List.map packageData >> BackendTask.combine)


packageData : PackageRoute -> BackendTask FatalError PackageData
packageData route =
    BackendTask.map2
        (PackageData route)
        (elmJsonFile route)
        (docsFile route)


docsFile : PackageRoute -> BackendTask FatalError (List ModuleDoc)
docsFile route =
    File.jsonFile (Decode.list moduleDocDecoder) (docsPath route)
        |> BackendTask.allowFatal


elmJsonFile : PackageRoute -> BackendTask FatalError ElmJson
elmJsonFile route =
    File.jsonFile elmJsonDecoder (elmJsonPath route)
        |> BackendTask.allowFatal


docsPath : PackageRoute -> String
docsPath route =
    packageDir route ++ "/docs.json"


elmJsonPath : PackageRoute -> String
elmJsonPath route =
    packageDir route ++ "/elm.json"


packageDir : PackageRoute -> String
packageDir route =
    "public/package-docs/packages/" ++ route.author ++ "/" ++ route.name ++ "/" ++ route.version


packageUrl : PackageRoute -> String
packageUrl route =
    "/packages/" ++ route.author ++ "/" ++ route.name ++ "/" ++ versionSlug route.version


moduleUrl : PackageRoute -> String -> String
moduleUrl route moduleName =
    packageUrl route ++ "/" ++ moduleSlug moduleName


modulePath : PackageRoute -> String -> List String
modulePath route moduleName =
    [ "packages", route.author, route.name, versionSlug route.version, moduleSlug moduleName ]


versionSlug : String -> String
versionSlug version =
    String.replace "." "-" version


versionFromSlug : String -> String
versionFromSlug slug =
    String.replace "-" "." slug


moduleSlug : String -> String
moduleSlug moduleName =
    String.replace "." "-" moduleName


moduleNameFromSlug : String -> String
moduleNameFromSlug slug =
    String.replace "-" "." slug


routeFromDocsPath : String -> Maybe PackageRoute
routeFromDocsPath path =
    case String.split "/" path of
        [ "public", "package-docs", "packages", author, name, version, "docs.json" ] ->
            Just { author = author, name = name, version = version }

        _ ->
            Nothing


isPublishedPackageRoute : PackageRoute -> Bool
isPublishedPackageRoute route =
    not
        (route.author
            == "elm-pebble"
            && List.member route.name [ "companion-protocol", "elm-phone" ]
        )


elmJsonDecoder : Decoder ElmJson
elmJsonDecoder =
    Decode.map7 ElmJson
        (Decode.field "name" Decode.string)
        (Decode.field "summary" Decode.string)
        (Decode.field "license" Decode.string)
        (Decode.field "version" Decode.string)
        (Decode.field "elm-version" Decode.string)
        (Decode.field "exposed-modules" exposedModulesDecoder)
        (Decode.field "dependencies" dependenciesDecoder)


exposedModulesDecoder : Decoder (List String)
exposedModulesDecoder =
    Decode.oneOf
        [ Decode.list Decode.string
        , Decode.dict (Decode.list Decode.string)
            |> Decode.map (Dict.toList >> List.concatMap Tuple.second)
        ]


dependenciesDecoder : Decoder (List ( String, String ))
dependenciesDecoder =
    Decode.dict Decode.string
        |> Decode.map (Dict.toList >> List.sortBy Tuple.first)


moduleDocDecoder : Decoder ModuleDoc
moduleDocDecoder =
    Decode.map5 ModuleDoc
        (Decode.field "name" Decode.string)
        (Decode.field "comment" Decode.string)
        (Decode.field "unions" (Decode.list unionDocDecoder))
        (Decode.field "aliases" (Decode.list aliasDocDecoder))
        (Decode.field "values" (Decode.list valueDocDecoder))


unionDocDecoder : Decoder UnionDoc
unionDocDecoder =
    Decode.map4 UnionDoc
        (Decode.field "name" Decode.string)
        (Decode.field "comment" Decode.string)
        (Decode.field "args" (Decode.list Decode.string))
        (Decode.field "cases" (Decode.list caseDecoder))


caseDecoder : Decoder ( String, List String )
caseDecoder =
    Decode.map2 Tuple.pair
        (Decode.index 0 Decode.string)
        (Decode.index 1 (Decode.list Decode.string))


aliasDocDecoder : Decoder AliasDoc
aliasDocDecoder =
    Decode.map4 AliasDoc
        (Decode.field "name" Decode.string)
        (Decode.field "comment" Decode.string)
        (Decode.field "args" (Decode.list Decode.string))
        (Decode.field "type" Decode.string)


valueDocDecoder : Decoder ValueDoc
valueDocDecoder =
    Decode.map3 ValueDoc
        (Decode.field "name" Decode.string)
        (Decode.field "comment" Decode.string)
        (Decode.field "type" Decode.string)
