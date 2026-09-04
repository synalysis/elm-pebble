module Main exposing (main)

import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Html exposing (Html, a, div, text)
import Html.Attributes as Attr
import Url


type Route
    = Home
    | About


type alias Model =
    { key : Nav.Key
    , route : Route
    }


type Msg
    = LinkClicked UrlRequest
    | UrlChanged Url.Url


parseRoute : Url.Url -> Route
parseRoute url =
    if url.path == "/about" then
        About
    else
        Home


routeLabel : Route -> String
routeLabel route =
    case route of
        Home ->
            "home"

        About ->
            "about"


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key, route = parseRoute url }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChanged url ->
            ( { model | route = parseRoute url }, Cmd.none )

        LinkClicked request ->
            case request of
                Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                External href ->
                    ( model, Nav.load href )


view : Model -> Html Msg
view model =
    div []
        [ text ("route: " ++ routeLabel model.route)
        , a [ Attr.href "/about" ] [ text "go about" ]
        , a [ Attr.href "/" ] [ text "go home" ]
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = \model -> { title = routeLabel model.route, body = [ view model ] }
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }
