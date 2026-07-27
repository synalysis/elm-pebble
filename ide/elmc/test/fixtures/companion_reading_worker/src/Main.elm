module Main exposing (main, readingString, updateFromPhone)

import Fixture.Types exposing (PhoneToWatch(..), Scale(..))
import Json.Decode as Decode
import Pebble.Platform as Platform
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources


type alias Model =
    { sample : Maybe Scale }


type Msg
    = FromPhone PhoneToWatch
    | ProbeReading Int
    | Noop


applyProbeReading : Int -> Model -> Model
applyProbeReading c10 model =
    updateFromPhone (GotReading (Celsius c10)) model


updateFromPhone : PhoneToWatch -> Model -> Model
updateFromPhone message model =
    case message of
        GotReading temperature ->
            { model | sample = Just temperature }


readingString : Model -> String
readingString model =
    case model.sample of
        Nothing ->
            "--"

        Just (Celsius c10) ->
            String.fromInt ((c10 + 5) // 10) ++ "C"

        Just (Fahrenheit f10) ->
            String.fromInt ((f10 + 5) // 10) ++ "F"


init : Platform.LaunchContext -> ( Model, Platform.Cmd Msg )
init _ =
    ( { sample = Nothing }, Cmd.none )


update : Msg -> Model -> ( Model, Platform.Cmd Msg )
update msg model =
    case msg of
        FromPhone phone ->
            ( updateFromPhone phone model, Cmd.none )

        ProbeReading c10 ->
            ( applyProbeReading c10 model, Cmd.none )

        Noop ->
            ( model, Cmd.none )


subscriptions : Model -> Platform.Sub Msg
subscriptions _ =
    Sub.none


view : Model -> PebbleUi.UiNode
view model =
    PebbleUi.windowStack
        [ PebbleUi.window 1
            [ PebbleUi.canvasLayer 1
                [ PebbleUi.clear PebbleColor.white
                , PebbleUi.textLabel UiResources.DefaultFont { x = 8, y = 40 } (readingString model)
                ]
            ]
        ]


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
