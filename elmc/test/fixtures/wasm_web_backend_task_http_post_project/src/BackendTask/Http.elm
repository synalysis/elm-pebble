module BackendTask.Http exposing (post, jsonBody, expectWhatever)

import Json.Encode as Encode
import Task exposing (Task)


type Body
    = EmptyBody
    | StringBody String String
    | JsonBody Encode.Value


type Expect error a
    = ExpectWhatever a


emptyBody : Body
emptyBody =
    EmptyBody


jsonBody : Encode.Value -> Body
jsonBody _ =
    EmptyBody


expectWhatever : a -> Expect error a
expectWhatever value =
    ExpectWhatever value


post : String -> Body -> Expect error a -> Task error a
post _ _ _ =
    Task.fail "stub"
