module CompanionApp exposing (main)

import Companion.GeneratedPreferences as GeneratedPreferences
import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import CompanionPreferences
import Json.Decode as Decode
import Pebble.Companion.Phone as CompanionPhone
import Platform


type alias Model =
    { settings : CompanionPreferences.Settings
    , errors : List String
    }


type alias Flags =
    Decode.Value


type Msg
    = FromWatch (Result String WatchToPhone)
    | FromBridge (Result String CompanionPreferences.Settings)


init : Flags -> ( Model, Cmd Msg )
init flags =
    case GeneratedPreferences.decodeConfigurationFlags flags of
        Ok (Just settings) ->
            ( { settings = settings, errors = [] }, sendSettings settings )

        Ok Nothing ->
            ( initialModel, sendSettings CompanionPreferences.defaults )

        Err error ->
            ( addError ("Initial configuration error: " ++ error) initialModel
            , sendSettings CompanionPreferences.defaults
            )


initialModel : Model
initialModel =
    { settings = CompanionPreferences.defaults, errors = [] }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestSettings) ->
            ( model, sendSettings model.settings )

        FromWatch (Err error) ->
            ( addError ("Watch message error: " ++ error) model, Cmd.none )

        FromBridge (Ok settings) ->
            ( { model | settings = settings }, sendSettings settings )

        FromBridge (Err error) ->
            ( addError ("Configuration error: " ++ error) model, Cmd.none )


addError : String -> Model -> Model
addError error model =
    { model | errors = model.errors ++ [ error ] }


sendSettings : CompanionPreferences.Settings -> Cmd Msg
sendSettings settings =
    Cmd.batch
        [ CompanionPhone.sendPhoneToWatch (SetMotivationalText settings.motivationalText)
        , CompanionPhone.sendPhoneToWatch (SetWatchDisplaySeconds (clampSeconds settings.watchSeconds))
        , CompanionPhone.sendPhoneToWatch (SetQuoteDisplaySeconds (clampSeconds settings.quoteSeconds))
        , CompanionPhone.sendPhoneToWatch (SetWatchBackground settings.watchBackground)
        , CompanionPhone.sendPhoneToWatch (SetWatchForeground settings.watchForeground)
        , CompanionPhone.sendPhoneToWatch (SetQuoteBackground settings.quoteBackground)
        , CompanionPhone.sendPhoneToWatch (SetQuoteTextColor settings.quoteText)
        ]


clampSeconds : Float -> Int
clampSeconds value =
    let
        rounded =
            round value
    in
    if rounded < 1 then
        1

    else
        rounded


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ CompanionPhone.onWatchToPhone FromWatch
        , GeneratedPreferences.onConfiguration FromBridge
        ]


main : Program Flags Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
