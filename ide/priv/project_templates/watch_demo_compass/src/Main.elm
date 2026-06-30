module Main exposing (main)

import Json.Decode as Decode
import Pebble.Button as Button
import Pebble.Compass as Compass
import Pebble.Events as Events
import Pebble.Platform as Platform
import Pebble.Ui as Ui
import Pebble.Ui.Color as Color
import Pebble.Ui.Resources as Resources


type alias Model =
    { hasCompass : Bool
    , heading : Maybe Compass.Heading
    , refreshes : Int
    }


type Msg
    = SelectPressed
    | GotHeading (Result Compass.Error Compass.Heading)
    | HeadingChanged Compass.Heading


init : Platform.LaunchContext -> ( Model, Cmd Msg )
init context =
    ( { hasCompass = context.hasCompass
      , heading = Nothing
      , refreshes = 0
      }
    , if context.hasCompass then
          Compass.current GotHeading

      else
          Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectPressed ->
            if model.hasCompass then
                ( { model | refreshes = model.refreshes + 1 }, Compass.current GotHeading )

            else
                ( model, Cmd.none )

        GotHeading result ->
            case result of
                Ok heading ->
                    ( { model | heading = Just heading }, Cmd.none )

                Err Compass.Unavailable ->
                    ( { model | heading = Nothing }, Cmd.none )

                Err Compass.InvalidReading ->
                    ( { model | heading = Nothing }, Cmd.none )

        HeadingChanged heading ->
            ( { model | heading = Just heading }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.hasCompass then
        Events.batch
            [ Compass.onChange HeadingChanged
            , Button.onPress Button.Select SelectPressed
            ]

    else
        Events.batch []


view : Model -> Ui.UiNode
view model =
    let
        textOpts =
            Ui.alignLeft Ui.defaultTextOptions
    in
    Ui.toUiNode
        [ Ui.clear Color.white
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 8, w = 136, h = 18 } "Compass"
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 32, w = 136, h = 18 } (headingLabel model.heading model.hasCompass)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 56, w = 136, h = 18 } (validLabel model.heading)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 80, w = 136, h = 18 } (String.fromInt model.refreshes)
        , Ui.text Resources.DefaultFont textOpts { x = 4, y = 104, w = 136, h = 18 } "Sel: peek"
        ]


headingLabel : Maybe Compass.Heading -> Bool -> String
headingLabel maybeHeading hasCompass =
    if not hasCompass then
        "No compass"

    else
        case maybeHeading of
            Nothing ->
                "--"

            Just heading ->
                if heading.isValid then
                    String.fromInt (round heading.degrees) ++ " deg"

                else
                    "Invalid"


validLabel : Maybe Compass.Heading -> String
validLabel maybeHeading =
    case maybeHeading of
        Nothing ->
            "Waiting"

        Just heading ->
            if heading.isValid then
                "Valid"

            else
                "Invalid"


round : Float -> Int
round value =
    if value >= 0 then
        floor (value + 0.5)

    else
        ceiling (value - 0.5)


main : Program Decode.Value Model Msg
main =
    Platform.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
