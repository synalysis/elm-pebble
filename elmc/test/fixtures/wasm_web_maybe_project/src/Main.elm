module Main exposing (main)

import Html exposing (Html, text)


flag : Bool -> String
flag value =
    if value then
        "1"

    else
        "0"


positive : Int -> Maybe Int
positive n =
    if n > 0 then
        Just (n * 2)

    else
        Nothing


main : Html String
main =
    text
        (String.join "|"
            [ "wd:" ++ flag (Maybe.withDefault 0 (Just 42) == 42)
            , "wn:" ++ flag (Maybe.withDefault 0 Nothing == 0)
            , "ws:" ++ flag (Maybe.withDefault "nope" (Just "yes") == "yes")
            , "we:" ++ flag (Maybe.withDefault "nope" Nothing == "nope")
            , "mp:" ++ flag (Maybe.map String.length (Just "cat") == Just 3)
            , "mn:" ++ flag (Maybe.map String.length Nothing == Nothing)
            , "at:" ++ flag (Maybe.andThen positive (Just 3) == Just 6)
            , "af:" ++ flag (Maybe.andThen positive (Just 0) == Nothing)
            , "an:" ++ flag (Maybe.andThen positive Nothing == Nothing)
            , "m2:" ++ flag (Maybe.map2 (+) (Just 1) (Just 2) == Just 3)
            , "m2n:" ++ flag (Maybe.map2 (+) Nothing (Just 2) == Nothing)
            , "m3:" ++ flag (Maybe.map3 (\a b c -> a + b + c) (Just 1) (Just 2) (Just 3) == Just 6)
            , "m4:" ++ flag (Maybe.map4 (\a b c d -> a + b + c + d) (Just 1) (Just 2) (Just 3) (Just 4) == Just 10)
            , "m5:" ++ flag (Maybe.map5 (\a b c d e -> a + b + c + d + e) (Just 1) (Just 2) (Just 3) (Just 4) (Just 5) == Just 15)
            ]
        )
