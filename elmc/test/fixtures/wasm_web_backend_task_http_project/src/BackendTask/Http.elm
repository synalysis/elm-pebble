module BackendTask.Http exposing (getJson)

import Json.Decode exposing (Decoder)
import Task exposing (Task)


getJson : String -> Decoder a -> Task String a
getJson _ _ =
    Debug.todo "stub"
