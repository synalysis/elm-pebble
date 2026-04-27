port module HeaderVariants exposing
    ( Model
    , Msg(..)
    , init
    , update
    , maybeInc
    , sumList
    )

import List as L exposing (foldl)
import Maybe as M exposing (Maybe(..), map, withDefault)

port toJs : String -> Cmd msg

type alias Model =
    { value : Int
    , payload : Maybe Int
    }

type Msg
    = Set Int
    | Clear

init : Int -> ( Model, Cmd Msg )
init n =
    ( { value = n, payload = Just n }, Cmd.none )

maybeInc : Maybe Int -> Int
maybeInc maybeValue =
    M.withDefault 0 (M.map ((+) 1) maybeValue)

sumList : List Int -> Int
sumList items =
    L.foldl (+) 0 items

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Set n ->
            ( { value = n, payload = Just n }, Cmd.none )

        Clear ->
            ( model, Cmd.none )
