module Main exposing (main, readingString, updateFromPhone)

import Companion.Types exposing (PhoneToWatch(..), Temperature(..))
import Json.Decode as Decode
import Pebble.Platform as Platform
import Pebble.Ui as PebbleUi
import Pebble.Ui.Color as PebbleColor
import Pebble.Ui.Resources as UiResources


type alias Model =
    { reading : Maybe Temperature }


type Msg
    = FromPhone PhoneToWatch
    | ProbeReading Int
    | ProbeReadingF Int
    | Noop


applyProbeReading : Int -> Model -> Model
applyProbeReading c10 model =
    updateFromPhone (ProvideTemperature (Celsius c10)) model


applyProbeReadingF : Int -> Model -> Model
applyProbeReadingF f10 model =
    updateFromPhone (ProvideTemperature (Fahrenheit f10)) model


updateFromPhone : PhoneToWatch -> Model -> Model
updateFromPhone message model =
    case message of
        ProvideTemperature temperature ->
            { model | reading = Just temperature }

        _ ->
            model


readingString : Model -> String
readingString model =
    case model.reading of
        Nothing ->
            "--"

        Just (Celsius c10) ->
            String.fromInt ((c10 + 5) // 10) ++ "C"

        Just (Fahrenheit f10) ->
            String.fromInt ((f10 + 5) // 10) ++ "F"


init : Platform.LaunchContext -> ( Model, Platform.Cmd Msg )
init _ =
    ( { reading = Nothing }, Cmd.none )


update : Msg -> Model -> ( Model, Platform.Cmd Msg )
update msg model =
    case msg of
        FromPhone phone ->
            ( updateFromPhone phone model, Cmd.none )

        ProbeReading c10 ->
            ( applyProbeReading c10 model, Cmd.none )

        ProbeReadingF f10 ->
            ( applyProbeReadingF f10 model, Cmd.none )

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
