module Main exposing (main)

import Browser
import Browser.Dom
import Html exposing (Html, text)
import Task


type alias Model =
    String


type Msg
    = Got (Result Browser.Dom.Error ( Browser.Dom.Viewport, Browser.Dom.Viewport, Browser.Dom.Element ))


init : () -> ( Model, Cmd Msg )
init _ =
    ( "wait"
    , Task.attempt Got <|
        Task.map3 (\windowVp boxVp box -> ( windowVp, boxVp, box ))
            Browser.Dom.getViewport
            (Browser.Dom.getViewportOf "box")
            (Browser.Dom.getElement "box")
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg _ =
    case msg of
        Got (Ok ( windowVp, boxVp, box )) ->
            ( formatViewport windowVp
                ++ ">"
                ++ formatViewport boxVp
                ++ "|"
                ++ formatElement box
            , Cmd.none
            )

        Got (Err _) ->
            ( "missing", Cmd.none )


formatViewport : Browser.Dom.Viewport -> String
formatViewport vp =
    n vp.scene.width
        ++ "x"
        ++ n vp.scene.height
        ++ "@"
        ++ n vp.viewport.x
        ++ ","
        ++ n vp.viewport.y
        ++ ":"
        ++ n vp.viewport.width
        ++ "x"
        ++ n vp.viewport.height


formatElement : Browser.Dom.Element -> String
formatElement el =
    n el.element.x
        ++ ","
        ++ n el.element.y
        ++ ":"
        ++ n el.element.width
        ++ "x"
        ++ n el.element.height


n : Float -> String
n value =
    String.fromInt (round value)


view : Model -> Html Msg
view model =
    text model


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
