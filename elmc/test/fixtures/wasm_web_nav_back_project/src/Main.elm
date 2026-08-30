module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html exposing (Html, text)
import Url


type alias Model =
    { key : Nav.Key }


type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ _ key =
    ( { key = key }, Nav.back key 2 )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : Model -> Browser.Document Msg
view _ =
    { title = "back"
    , body = [ text "ok" ]
    }


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }
