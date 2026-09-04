module BackendTask.Http exposing (get, post, expectBytes, bytesBody, expectWhatever, emptyBody)

import Bytes exposing (Bytes)
import Bytes.Decode exposing (Decoder)
import Task exposing (Task)


type Body
    = EmptyBody
    | BytesBody String Bytes


type Expect error a
    = ExpectBytes (Decoder a)
    | ExpectWhatever a


emptyBody : Body
emptyBody =
    EmptyBody


bytesBody : String -> Bytes -> Body
bytesBody _ _ =
    EmptyBody


expectBytes : Decoder a -> Expect error a
expectBytes decoder =
    ExpectBytes decoder


expectWhatever : a -> Expect error a
expectWhatever value =
    ExpectWhatever value


get : String -> Expect error a -> Task error a
get _ _ =
    Debug.todo "stub"


post : String -> Body -> Expect error a -> Task error a
post _ _ _ =
    Debug.todo "stub"
