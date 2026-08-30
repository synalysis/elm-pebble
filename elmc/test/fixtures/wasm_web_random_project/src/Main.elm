module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Random


type alias Model =
    { constant : String
    , ints : String
    }


type Msg
    = GotConst String
    | GotInts (List Int)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotConst value ->
            ( { model | constant = value }, Cmd.none )

        GotInts values ->
            ( { model | ints = String.join "," (List.map String.fromInt values) }, Cmd.none )


view : Model -> Html Msg
view model =
    text (model.constant ++ ":" ++ model.ints)


init : () -> ( Model, Cmd Msg )
init _ =
    ( { constant = "pending", ints = "pending" }
    , Cmd.batch
        [ Random.generate GotConst (Random.constant "ok")
        , Random.generate GotInts (Random.list 3 (Random.int 7 7))
        ]
    )


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
