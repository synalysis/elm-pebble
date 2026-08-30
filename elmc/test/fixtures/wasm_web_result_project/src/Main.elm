module Main exposing (main)

import Html exposing (Html, text)


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


doublePositive : Int -> Result String Int
doublePositive n =
    if n > 0 then
        Ok (n * 2)

    else
        Err "no"


main : Html String
main =
    text
        (String.join "|"
            [ "wd:" ++ flag (Result.withDefault 0 (Ok 42) == 42)
            , "we:" ++ flag (Result.withDefault 0 (Err "x") == 0)
            , "ws:" ++ flag (Result.withDefault "nope" (Ok "yes") == "yes")
            , "wn:" ++ flag (Result.withDefault "nope" (Err 1) == "nope")
            , "mp:" ++ flag (Result.map String.length (Ok "cat") == Ok 3)
            , "me:" ++ flag (Result.map String.length (Err "x") == Err "x")
            , "mx:" ++ flag (Result.mapError String.length (Err "cat") == Err 3)
            , "mo:" ++ flag (Result.mapError String.length (Ok "cat") == Ok "cat")
            , "at:" ++ flag (Result.andThen doublePositive (Ok 3) == Ok 6)
            , "af:" ++ flag (Result.andThen doublePositive (Ok 0) == Err "no")
            , "ae:" ++ flag (Result.andThen doublePositive (Err "x") == Err "x")
            , "tm:" ++ flag (Result.toMaybe (Ok 1) == Just 1)
            , "tn:" ++ flag (Result.toMaybe (Err "x") == Nothing)
            , "fm:" ++ flag (Result.fromMaybe "missing" (Just 5) == Ok 5)
            , "fn:" ++ flag (Result.fromMaybe "missing" Nothing == Err "missing")
            , "m2:" ++ flag (Result.map2 (+) (Ok 1) (Ok 2) == Ok 3)
            , "m2e:" ++ flag (Result.map2 (+) (Err "a") (Ok 2) == Err "a")
            , "m3:" ++ flag (Result.map3 (\a b c -> a + b + c) (Ok 1) (Ok 2) (Ok 3) == Ok 6)
            , "m3e:" ++ flag (Result.map3 (\a b c -> a + b + c) (Ok 1) (Err "x") (Ok 3) == Err "x")
            , "m4:" ++ flag (Result.map4 (\a b c d -> a + b + c + d) (Ok 1) (Ok 2) (Ok 3) (Ok 4) == Ok 10)
            , "m5:" ++ flag (Result.map5 (\a b c d e -> a + b + c + d + e) (Ok 1) (Ok 2) (Ok 3) (Ok 4) (Ok 5) == Ok 15)
            , "m4e:" ++ flag (Result.map4 (\a b c d -> a + b + c + d) (Ok 1) (Err "x") (Ok 3) (Ok 4) == Err "x")
            ]
        )
