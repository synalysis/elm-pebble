module TsDerivedPatterns exposing
    ( composeWithLambda
    , constructorRefJust
    , nestedCaseCtor
    , nestedFieldCall
    , childHandler
    , qualifiedRefIdentity
    , unicodeMathAlpha
    , Sticky(..)
    )

{-|

Patterns distilled from tree-sitter corpus sources that previously
exercised parser/AST shapes missing from elmc/elmx fixture coverage:

- nested field-call receiver (`the-sett/salix` Json.Coding)
- compose-right into lambda (`SiriusStarr/elm-review-no-single-pattern-case`)
- qualified/constructor refs as values
- nested `Just (Ctor x)` case branches (`NoRedInk/noredink-ui` SortableTable)
- unicode surrogate pair literals (`hecrj/html-parser` NamedCharacterReferences)

-}

import Basics


type alias Api =
    { child : Child -> Handler }


type alias Child =
    { getName : String -> Int }


type alias Handler =
    { read : String -> Int }


childHandler : Child -> Handler
childHandler child =
    { read = child.getName }


nestedFieldCall : Api -> Child -> String -> Int
nestedFieldCall api child key =
    (api.child child).read key


composeWithLambda : Int -> Int
composeWithLambda value =
    let
        pipeline =
            String.fromInt
                >> String.length
    in
    pipeline value


qualifiedRefIdentity : Int -> Int
qualifiedRefIdentity n =
    Basics.identity n


constructorRefJust : Int -> Maybe Int
constructorRefJust =
    Just


type Sticky
    = Default
    | Custom Int


nestedCaseCtor : Maybe Sticky -> Int
nestedCaseCtor sticky =
    case sticky of
        Nothing ->
            0

        Just Default ->
            1

        Just (Custom n) ->
            n


unicodeMathAlpha : String
unicodeMathAlpha =
    "\u{1D404}"
