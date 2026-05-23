module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), Theme(..), Units(..), WatchToPhone(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Phone as Phone
import Pebble.Companion.PreferenceStore as PreferenceStore
import Pebble.Companion.Storage as Storage
import Platform


type alias Model =
    { theme : Theme
    , units : Units
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotStorage (Result Storage.Error Storage.Value)
    | GotPreference (Result String ( String, Encode.Value ))
    | StoredTheme (Result Storage.Error Storage.Value)
    | StoredUnits (Result String ( String, Encode.Value ))


init : () -> ( Model, Cmd Msg )
init _ =
    ( { theme = Dark, units = Metric }, requestValues )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestStoredValues) ->
            ( model, requestValues )

        FromWatch (Ok CycleTheme) ->
            let
                nextTheme =
                    case model.theme of
                        Dark ->
                            Light

                        Light ->
                            Dark

                nextUnits =
                    case model.units of
                        Metric ->
                            Imperial

                        Imperial ->
                            Metric
            in
            ( model
            , Cmd.batch
                [ Storage.set "theme" (Storage.StringValue (themeToString nextTheme))
                , PreferenceStore.set "units" (Encode.string (unitsToString nextUnits))
                , Storage.get "theme" StoredTheme
                , PreferenceStore.get "units" StoredUnits
                ]
            )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotStorage (Ok (Storage.StringValue themeText)) ->
            case themeFromString themeText of
                Just theme ->
                    ( { model | theme = theme }
                    , pushValues theme model.units
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotStorage _ ->
            ( model, Cmd.none )

        GotPreference (Ok ( "units", value )) ->
            case Decode.decodeValue Decode.string value |> Result.andThen unitsFromString of
                Ok units ->
                    ( { model | units = units }
                    , pushValues model.theme units
                    )

                Err _ ->
                    ( model, Cmd.none )

        GotPreference _ ->
            ( model, Cmd.none )

        StoredTheme (Ok (Storage.StringValue themeText)) ->
            case themeFromString themeText of
                Just theme ->
                    ( { model | theme = theme }, pushValues theme model.units )

                Nothing ->
                    ( model, Cmd.none )

        StoredTheme _ ->
            ( model, Cmd.none )

        StoredUnits (Ok ( "units", value )) ->
            case Decode.decodeValue Decode.string value |> Result.andThen unitsFromString of
                Ok units ->
                    ( { model | units = units }, pushValues model.theme units )

                Err _ ->
                    ( model, Cmd.none )

        StoredUnits _ ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Phone.onWatchToPhone FromWatch
        , Storage.onStorage GotStorage
        , PreferenceStore.onPreference GotPreference
        ]


main : Platform.Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }


requestValues : Cmd Msg
requestValues =
    Cmd.batch
        [ Storage.setup
        , PreferenceStore.setup
        , Storage.get "theme" GotStorage
        , PreferenceStore.get "units" GotPreference
        ]


pushValues : Theme -> Units -> Cmd Msg
pushValues theme units =
    Phone.sendPhoneToWatch (ProvideTheme theme units)


themeToString : Theme -> String
themeToString theme =
    case theme of
        Dark ->
            "dark"

        Light ->
            "light"


themeFromString : String -> Maybe Theme
themeFromString text =
    case text of
        "dark" ->
            Just Dark

        "light" ->
            Just Light

        _ ->
            Nothing


unitsToString : Units -> String
unitsToString units =
    case units of
        Metric ->
            "metric"

        Imperial ->
            "imperial"


unitsFromString : String -> Result String Units
unitsFromString text =
    case text of
        "metric" ->
            Ok Metric

        "imperial" ->
            Ok Imperial

        _ ->
            Err "unknown units"
