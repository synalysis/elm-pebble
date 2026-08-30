module Main exposing (main)

import Html exposing (Html, text)
import Json.Decode as Decode


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


has : String -> String -> Bool
has needle got =
    String.contains needle got


show : Result Decode.Error a -> String
show result =
    case result of
        Ok _ ->
            "ok"

        Err err ->
            Decode.errorToString err


main : Html String
main =
    let
        missingText =
            show (Decode.decodeString (Decode.field "missing" Decode.int) "{}")

        fieldText =
            show (Decode.decodeString (Decode.field "x" Decode.int) "{\"x\":true}")

        parseText =
            show (Decode.decodeString Decode.int "not-json")

        oneOfText =
            show
                (Decode.decodeString
                    (Decode.oneOf [ Decode.int, Decode.bool |> Decode.andThen (\_ -> Decode.fail "nb") ])
                    "\"z\""
                )

        emptyOneOfText =
            show (Decode.decodeString (Decode.oneOf []) "1")

        singleOneOfText =
            show (Decode.decodeString (Decode.oneOf [ Decode.int ]) "true")

        prettyFailText =
            show (Decode.decodeString Decode.int "{\"x\":1}")
    in
    text
        (String.join "|"
            [ "mf:"
                ++ flag
                    (has "Problem with the given value:" missingText
                        && has "{}" missingText
                        && has "Expecting an OBJECT with a field named `missing`" missingText
                    )
            , "xf:"
                ++ flag
                    (has "Problem with the value at json.x:" fieldText
                        && has "true" fieldText
                        && has "Expecting an INT" fieldText
                    )
            , "pj:" ++ flag (has "This is not valid JSON!" parseText)
            , "oo:"
                ++ flag
                    (has "Json.Decode.oneOf failed in the following 2 ways:" oneOfText
                        && has "(1)" oneOfText
                        && has "(2)" oneOfText
                    )
            , "oe:" ++ flag (has "Ran into a Json.Decode.oneOf with no possibilities!" emptyOneOfText)
            , "os:"
                ++ flag
                    (has "Problem with the given value:" singleOneOfText
                        && has "Expecting an INT" singleOneOfText
                        && not (has "failed in the following" singleOneOfText)
                    )
            , "pp:"
                ++ flag
                    (has "Problem with the given value:" prettyFailText
                        && has "{\n        \"x\": 1\n    }" prettyFailText
                        && has "Expecting an INT" prettyFailText
                    )
            ]
        )
