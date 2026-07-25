port module Main exposing (main)

import Browser
import Browser.Navigation as Nav exposing (UrlRequest(..))
import Bytes exposing (Bytes)
import Bytes.Decode as Decode
import Html exposing (Html, a, div, text)
import Html.Attributes as Attr
import Url


port pageDataFromJs : (Bytes -> msg) -> Sub msg


type alias Model =
    { key : Nav.Key
    , routeId : Int
    }


type Msg
    = LinkClicked UrlRequest
    | UrlChanged Url.Url
    | RouteData Bytes


routeTitle : Int -> String
routeTitle id =
    case id of
        2 ->
            "about"

        _ ->
            "home"


decodeRouteId : Bytes -> Int
decodeRouteId bytes =
    Decode.decode Decode.unsignedInt8 bytes
        |> Maybe.withDefault 0


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ _ key =
    ( { key = key, routeId = 0 }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RouteData bytes ->
            ( { model | routeId = decodeRouteId bytes }, Cmd.none )

        UrlChanged _ ->
            ( model, Cmd.none )

        LinkClicked request ->
            case request of
                Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                External href ->
                    ( model, Nav.load href )


view : Model -> Html Msg
view model =
    div []
        [ text ("data: " ++ routeTitle model.routeId)
        , a [ Attr.href "/about" ] [ text "about" ]
        , a [ Attr.href "/" ] [ text "home" ]
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    pageDataFromJs RouteData


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = \model -> { title = routeTitle model.routeId, body = [ view model ] }
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }
