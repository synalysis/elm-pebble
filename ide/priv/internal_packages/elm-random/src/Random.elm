module Random exposing
    ( Generator
    , Seed
    , andThen
    , bool
    , constant
    , float
    , generate
    , initialSeed
    , int
    , list
    , map
    , map2
    , map3
    , map4
    , map5
    , maxInt
    , minInt
    , pair
    , step
    , uniform
    , weighted
    )

{-| Deterministic random value generators.

This is the built-in `elm/random` implementation for Pebble runtimes. The API
matches the official package shape closely enough for application code and
debugger previews; native runtimes execute `generate` through a Pebble command.

-}

import Elm.Kernel.Random


type Generator a
    = Generator (Seed -> ( a, Seed ))


type Seed
    = Seed Int


minInt : Int
minInt =
    -2147483648


maxInt : Int
maxInt =
    2147483647


initialSeed : Int -> Seed
initialSeed value =
    Seed (normalizeSeed value)


step : Generator a -> Seed -> ( a, Seed )
step (Generator run) seed =
    run seed


generate : (a -> msg) -> Generator a -> Cmd msg
generate =
    Elm.Kernel.Random.generate


int : Int -> Int -> Generator Int
int low high =
    Generator <|
        \seed ->
            let
                ( raw, nextSeed ) =
                    next seed

                lo =
                    Basics.min low high

                hi =
                    Basics.max low high

                span =
                    hi - lo + 1
            in
            ( lo + modBy span raw, nextSeed )


float : Float -> Float -> Generator Float
float low high =
    map
        (\raw ->
            let
                lo =
                    Basics.min low high

                hi =
                    Basics.max low high
            in
            lo + ((toFloat raw / toFloat 2147483647) * (hi - lo))
        )
        (int 0 2147483647)


bool : Generator Bool
bool =
    map (\value -> value == 1) (int 0 1)


constant : a -> Generator a
constant value =
    Generator <| \seed -> ( value, seed )


map : (a -> b) -> Generator a -> Generator b
map fn generator =
    Generator <|
        \seed ->
            let
                ( value, nextSeed ) =
                    step generator seed
            in
            ( fn value, nextSeed )


map2 : (a -> b -> c) -> Generator a -> Generator b -> Generator c
map2 fn first second =
    Generator <|
        \seed ->
            let
                ( a, seedA ) =
                    step first seed

                ( b, seedB ) =
                    step second seedA
            in
            ( fn a b, seedB )


map3 : (a -> b -> c -> d) -> Generator a -> Generator b -> Generator c -> Generator d
map3 fn a b c =
    map2 (\ab cValue -> ab cValue) (map2 fn a b) c


map4 : (a -> b -> c -> d -> e) -> Generator a -> Generator b -> Generator c -> Generator d -> Generator e
map4 fn a b c d =
    map2 (\abc dValue -> abc dValue) (map3 fn a b c) d


map5 : (a -> b -> c -> d -> e -> f) -> Generator a -> Generator b -> Generator c -> Generator d -> Generator e -> Generator f
map5 fn a b c d e =
    map2 (\abcd eValue -> abcd eValue) (map4 fn a b c d) e


andThen : (a -> Generator b) -> Generator a -> Generator b
andThen fn generator =
    Generator <|
        \seed ->
            let
                ( value, nextSeed ) =
                    step generator seed
            in
            step (fn value) nextSeed


pair : Generator a -> Generator b -> Generator ( a, b )
pair =
    map2 Tuple.pair


list : Int -> Generator a -> Generator (List a)
list count generator =
    if count <= 0 then
        constant []

    else
        map2 (::) generator (list (count - 1) generator)


uniform : a -> List a -> Generator a
uniform first rest =
    let
        values =
            first :: rest
    in
    map
        (\index ->
            values
                |> List.drop index
                |> List.head
                |> Maybe.withDefault first
        )
        (int 0 (List.length values - 1))


weighted : ( Float, a ) -> List ( Float, a ) -> Generator a
weighted first rest =
    let
        entries =
            first :: rest

        total =
            entries
                |> List.map (\( weight, _ ) -> Basics.max 0 weight)
                |> List.sum
    in
    if total <= 0 then
        constant (Tuple.second first)

    else
        map (pickWeighted (Tuple.second first) entries) (float 0 total)


pickWeighted : a -> List ( Float, a ) -> Float -> a
pickWeighted fallback entries target =
    case entries of
        [] ->
            fallback

        ( weight, value ) :: rest ->
            let
                clamped =
                    Basics.max 0 weight
            in
            case rest of
                [] ->
                    value

                _ ->
                    if target <= clamped then
                        value

                    else
                        pickWeighted fallback rest (target - clamped)


next : Seed -> ( Int, Seed )
next (Seed seed) =
    let
        advanced =
            normalizeSeed ((seed * 1103515245) + 12345)
    in
    ( advanced, Seed advanced )


normalizeSeed : Int -> Int
normalizeSeed value =
    let
        normalized =
            modBy 2147483647 value
    in
    if normalized <= 0 then
        normalized + 2147483647

    else
        normalized
