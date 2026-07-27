module BackendTask.Http exposing (getWithOptions, expectJson, Error(..))

import Json.Decode exposing (Decoder)
import Task exposing (Task)


type alias Metadata =
    { url : String
    , statusCode : Int
    , statusText : String
    , headers : List ( String, String )
    }


type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Metadata String
    | BadBody (Maybe Json.Decode.Error) String


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


getWithOptions : RequestOptions Error a -> Task Error a
getWithOptions _ =
    Task.fail (BadUrl "stub")
