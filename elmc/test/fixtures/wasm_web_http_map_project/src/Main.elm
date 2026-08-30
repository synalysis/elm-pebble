module Main exposing (main)

import Browser
import Html exposing (Html, text)
import Http


type Inner
    = Got (Result Http.Error String)


type Msg
    = Wrapped Inner


update : Msg -> String -> ( String, Cmd Msg )
update msg _ =
    case msg of
        Wrapped (Got _) ->
            ( "mapped", Cmd.none )


view : String -> Html Msg
view model =
    text model


init : () -> ( String, Cmd Msg )
init _ =
    ( "pending"
    , Cmd.map Wrapped
        (Http.get
            { url = "https://example.com/mapped"
            , expect = Http.expectString Got
            }
        )
    )


main : Program () String Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
