module Main exposing (main)

import Bytes.Decode as Decode exposing (Decoder, Step(..))
import Bytes.Encode as Encode
import Html exposing (Html, text)


list : Decoder a -> Decoder (List a)
list decoder =
    Decode.unsignedInt8
        |> Decode.andThen (\len -> Decode.loop ( len, [] ) (listStep decoder))


listStep : Decoder a -> ( Int, List a ) -> Decoder (Step ( Int, List a ) (List a))
listStep decoder ( n, xs ) =
    if n <= 0 then
        Decode.succeed (Done xs)

    else
        Decode.map (\x -> Loop ( n - 1, x :: xs )) decoder


main : Html String
main =
    let
        bytes =
            Encode.encode
                (Encode.sequence
                    [ Encode.unsignedInt8 3
                    , Encode.unsignedInt8 10
                    , Encode.unsignedInt8 20
                    , Encode.unsignedInt8 30
                    ]
                )
    in
    if Decode.decode (list Decode.unsignedInt8) bytes == Just [ 30, 20, 10 ] then
        text "ok"

    else
        text "fail"
