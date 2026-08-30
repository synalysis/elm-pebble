module Main exposing (main)

import Bytes.Decode as Decode
import Bytes.Encode as Encode
import Html exposing (Html, text)


main : Html String
main =
    let
        bytes =
            Encode.encode (Encode.unsignedInt8 1)
    in
    if Decode.decode Decode.fail bytes == Nothing then
        text "ok"

    else
        text "fail"
