module Main exposing
    ( Msg(..)
    , fromA
    , fromB
    , fromBPair
    , fromLocal
    , matchA
    , matchB
    , matchBPair
    , matchLocal
    , main
    )

import A
import B
import Platform


type Msg
    = Other
    | Wrap Int


fromA : A.Msg
fromA =
    A.Wrap 1


fromB : B.Msg
fromB =
    B.Wrap 2


fromBPair : B.Msg
fromBPair =
    B.Pair 4 5


fromLocal : Msg
fromLocal =
    Wrap 3


matchA : A.Msg -> Int
matchA msg =
    case msg of
        A.Wrap x ->
            x


matchB : B.Msg -> Int
matchB msg =
    case msg of
        B.Wrap 7 ->
            1

        B.Wrap x ->
            x

        B.Pair _ _ ->
            0

        B.Other ->
            0


matchBPair : B.Msg -> Int
matchBPair msg =
    case msg of
        B.Pair x y ->
            x + y

        _ ->
            0


matchLocal : Msg -> Int
matchLocal msg =
    case msg of
        Wrap x ->
            x

        Other ->
            0


main : Program () Msg Msg
main =
    Platform.worker
        { init = \_ -> ( Wrap 0, Cmd.none )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
