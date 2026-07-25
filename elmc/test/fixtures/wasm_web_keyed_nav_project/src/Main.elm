module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (id)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed


type alias Model =
    { swapped : Bool }


type Msg
    = Swap


init : Model
init =
    { swapped = False }


update : Msg -> Model -> Model
update Swap model =
    { model | swapped = not model.swapped }


items : Bool -> List ( String, Html Msg )
items swapped =
    if swapped then
        [ ( "b", div [ id "item-b" ] [ text "B" ] )
        , ( "a", div [ id "item-a" ] [ text "A" ] )
        ]

    else
        [ ( "a", div [ id "item-a" ] [ text "A" ] )
        , ( "b", div [ id "item-b" ] [ text "B" ] )
        ]


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Swap ] [ text "swap" ]
        , Keyed.node "div" [] (items model.swapped)
        ]


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
