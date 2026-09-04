module BackendTask.Http exposing (get, expectString)

import Json.Decode exposing (Decoder)
import Task exposing (Task)


type Expect error a
    = ExpectString (String -> a)


expectString : Expect error String
expectString =
    ExpectString identity


get : String -> Expect error a -> Task error a
get _ _ =
    Debug.todo "stub"
