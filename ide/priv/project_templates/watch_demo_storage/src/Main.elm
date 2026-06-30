module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Storage as Storage
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


storageKey : Int
storageKey =
    1


type alias Model =
    { value : Maybe Int
    , maxBytes : Maybe Int
    , writes : Int
    }


type Msg
    = SelectPressed
    | UpPressed
    | DownPressed
    | GotValue Int
    | GotMaxSize Int


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init _ =
    ( { value = Nothing, maxBytes = Nothing, writes = 0 }
    , Cmd.batch
        [ Storage.readInt storageKey GotValue
        , Storage.maxSize GotMaxSize
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            let
                next =
                    Maybe.withDefault 0 model.value + 1
            in
            ( { model | writes = model.writes + 1, value = Just next }
            , Storage.writeInt storageKey next
            )

        UpPressed ->
            ( model, Storage.readInt storageKey GotValue )

        DownPressed ->
            ( { model | value = Nothing }
            , Storage.delete storageKey
            )

        GotValue stored ->
            ( { model | value = Just stored }, Cmd.none )

        GotMaxSize bytes ->
            ( { model | maxBytes = Just bytes }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Events.batch
        [ Button.onPress Button.Select SelectPressed
        , Button.onPress Button.Up UpPressed
        , Button.onPress Button.Down DownPressed
        ]


view : Model -> Ui.UiNode
view model =
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 8, w = 136, h = 18 } "Storage demo"
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 32, w = 136, h = 18 } ("Value: " ++ maybeInt model.value)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 56, w = 136, h = 18 } ("Max: " ++ maybeInt model.maxBytes)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 80, w = 136, h = 18 } ("Writes: " ++ String.fromInt model.writes)
        , Ui.text Resources.DefaultFont Ui.defaultTextOptions { x = 4, y = 104, w = 136, h = 18 } "Select:+1 Up:read Down:delete"
        ]


maybeInt : Maybe Int -> String
maybeInt maybeValue =
    case maybeValue of
        Nothing ->
            "--"

        Just value ->
            String.fromInt value


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
