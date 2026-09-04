module Main exposing (main)

import Bytes exposing (Endianness(..))
import Bytes.Decode as Decode
import Bytes.Encode as Encode
import Html exposing (Html, text)


main : Html String
main =
    let
        i8 =
            Decode.decode Decode.signedInt8 (Encode.encode (Encode.signedInt8 -5)) == Just -5

        u16 =
            Decode.decode (Decode.unsignedInt16 BE) (Encode.encode (Encode.unsignedInt16 BE 7)) == Just 7

        i16le =
            Decode.decode (Decode.signedInt16 LE) (Encode.encode (Encode.signedInt16 LE -8)) == Just -8

        f32 =
            Decode.decode (Decode.float32 BE) (Encode.encode (Encode.float32 BE 1.5)) == Just 1.5

        utf8 =
            Decode.decode (Decode.string 3) (Encode.encode (Encode.string "$20")) == Just "$20"

        u32 =
            Decode.decode (Decode.unsignedInt32 BE) (Encode.encode (Encode.unsignedInt32 BE 16909060)) == Just 16909060

        i32le =
            Decode.decode (Decode.signedInt32 LE) (Encode.encode (Encode.signedInt32 LE -9)) == Just -9

        f64 =
            Decode.decode (Decode.float64 BE) (Encode.encode (Encode.float64 BE 2.5)) == Just 2.5

        blob =
            case Decode.decode (Decode.bytes 2) (Encode.encode (Encode.sequence [ Encode.unsignedInt8 1, Encode.unsignedInt8 2, Encode.unsignedInt8 3 ])) of
                Just sliced ->
                    Bytes.width sliced == 2

                Nothing ->
                    False

        utf8w =
            Bytes.getStringWidth "é" == Just 2 && Bytes.getStringWidth "a" == Just 1
    in
    if i8 && u16 && i16le && f32 && utf8 && u32 && i32le && f64 && blob && utf8w then
        text "ok"

    else
        text "fail"
