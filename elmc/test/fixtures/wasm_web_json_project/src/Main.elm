module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode
import Json.Encode as Encode


main : Html String
main =
    let
        decoded =
            Decode.decodeString Decode.int "42"

        encoded =
            Encode.encode 0 (Encode.object [ ( "x", Encode.int 1 ) ])

        prettyOk =
            Encode.encode 4 (Encode.object [ ( "x", Encode.int 1 ) ])
                == "{\n    \"x\": 1\n}"

        nullOk =
            Encode.encode 0 Encode.null
                == "null"
                && (case Decode.decodeString (Decode.null 42) "null" of
                        Ok 42 ->
                            True

                        _ ->
                            False
                   )
    in
    case decoded of
        Ok n ->
            text
                ("int:"
                    ++ String.fromInt n
                    ++ " json:"
                    ++ encoded
                    ++ " null:"
                    ++ (if nullOk then
                            "1"

                        else
                            "0"
                       )
                    ++ " pretty:"
                    ++ (if prettyOk then
                            "1"

                        else
                            "0"
                       )
                )

        Err _ ->
            text "decode failed"
