module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


type alias Rec =
    { z : Int
    , y : Int
    , x : Int
    , w : Int
    , v : Int
    , u : Int
    , t : Int
    , s : String
    }


decoder : Decode.Decoder Rec
decoder =
    Decode.map8 Rec
        (Decode.field "z" Decode.int)
        (Decode.field "y" Decode.int)
        (Decode.field "x" Decode.int)
        (Decode.field "w" Decode.int)
        (Decode.field "v" Decode.int)
        (Decode.field "u" Decode.int)
        (Decode.field "t" Decode.int)
        (Decode.field "s" Decode.string)


main : Html String
main =
    case Decode.decodeString decoder "{\"z\":1,\"y\":2,\"x\":3,\"w\":4,\"v\":5,\"u\":6,\"t\":7,\"s\":\"ok\"}" of
        Ok rec ->
            text
                (String.fromInt rec.z
                    ++ ":"
                    ++ String.fromInt rec.y
                    ++ ":"
                    ++ String.fromInt rec.x
                    ++ ":"
                    ++ String.fromInt rec.w
                    ++ ":"
                    ++ String.fromInt rec.v
                    ++ ":"
                    ++ String.fromInt rec.u
                    ++ ":"
                    ++ String.fromInt rec.t
                    ++ ":"
                    ++ rec.s
                )

        Err _ ->
            text "fail"
