module Main exposing (main)

import File exposing (File)
import Html exposing (Html, text)
import Json.Decode as Decode
import Time


describe : File -> String
describe file =
    String.join ","
        [ File.name file
        , File.mime file
        , String.fromInt (File.size file)
        , String.fromInt (Time.posixToMillis (File.lastModified file))
        ]


main : Decode.Value -> Html String
main value =
    case Decode.decodeValue (Decode.field "files" (Decode.list File.decoder)) value of
        Ok files ->
            text (String.join ";" (List.map describe files))

        Err _ ->
            text "fail"
