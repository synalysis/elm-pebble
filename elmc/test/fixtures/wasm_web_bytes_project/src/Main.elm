module Main exposing (main, probeDecode)

import Bytes
import Bytes.Decode as Decode
import Bytes.Encode as Encode
import Html exposing (Html, text)


main : Html String
main =
    probeDecode sampleBytes


probeDecode : Bytes.Bytes -> Html String
probeDecode bytes =
    case Decode.decode Decode.unsignedInt8 bytes of
        Just n ->
            text ("byte:" ++ String.fromInt n)

        Nothing ->
            text "decode failed"


sampleBytes : Bytes.Bytes
sampleBytes =
    Encode.encode (Encode.unsignedInt8 42)
