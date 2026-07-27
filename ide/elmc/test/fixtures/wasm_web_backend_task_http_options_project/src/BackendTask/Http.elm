module BackendTask.Http exposing (getJson, getWithOptions, expectJson, withMetadata, IgnoreCache)

import Json.Decode exposing (Decoder)
import Task exposing (Task)


type alias Metadata =
    { url : String
    , statusCode : Int
    , statusText : String
    , headers : List ( String, String )
    }


type alias RequestOptions error a =
    { url : String
    , expect : Expect error a
    , headers : List ( String, String )
    , cacheStrategy : Maybe CacheStrategy
    , retries : Maybe Int
    , timeoutInMs : Maybe Int
    , cachePath : Maybe String
    }


type Expect error a
    = ExpectJson (Decoder a)


type CacheStrategy
    = IgnoreCache


expectJson : Decoder a -> Expect error a
expectJson decoder =
    ExpectJson decoder


withMetadata : (Metadata -> a -> b) -> Expect error a -> Expect error b
withMetadata _ expect =
    expect


getWithOptions : RequestOptions error a -> Task error a
getWithOptions _ =
    Task.fail "stub"


getJson : String -> Decoder a -> Task String a
getJson _ _ =
    Task.fail "stub"
