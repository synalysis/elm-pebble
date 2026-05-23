module CompanionApp exposing (main)

import Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Pebble.Companion.Phone as Phone
import Pebble.Companion.PreferenceStore as PreferenceStore
import Pebble.Companion.Storage as Storage
import Platform


type alias Model =
    { theme : String
    , units : String
    }


type Msg
    = FromWatch (Result String WatchToPhone)
    | GotStorage (Result Storage.Error Storage.Value)
    | GotPreference (Result String ( String, Encode.Value ))
    | StoredTheme (Result Storage.Error Storage.Value)
    | StoredUnits (Result String ( String, Encode.Value ))


init : () -> ( Model, Cmd Msg )
init _ =
    ( { theme = "dark", units = "metric" }, requestValues )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromWatch (Ok RequestStoredValues) ->
            ( model, requestValues )

        FromWatch (Ok CycleTheme) ->
            let
                nextTheme =
                    if model.theme == "dark" then
                        "light"

                    else
                        "dark"
            in
            ( model
            , Cmd.batch
                [ Storage.set "theme" (Storage.StringValue nextTheme)
                , PreferenceStore.set "units"
                    (if model.units == "metric" then
                        Encode.string "imperial"

                     else
                        Encode.string "metric"
                    )
                , Storage.get "theme" StoredTheme
                , PreferenceStore.get "units" StoredUnits
                ]
            )

        FromWatch (Err _) ->
            ( model, Cmd.none )

        GotStorage (Ok (Storage.StringValue theme)) ->
            ( { model | theme = theme }
            , Cmd.none
            )

        GotStorage _ ->
            ( model, Cmd.none )

        GotPreference (Ok ( "units", value )) ->
            case Decode.decodeValue Decode.string value of
                Ok units ->
                    ( { model | units = units }
                    , pushValues model.theme units
                    )

                Err _ ->
                    ( model, Cmd.none )

        GotPreference _ ->
            ( model, Cmd.none )

        StoredTheme (Ok (Storage.StringValue theme)) ->
            ( { model | theme = theme }, Cmd.none )

        StoredTheme _ ->
            ( model, Cmd.none )

        StoredUnits (Ok ( "units", value )) ->
            case Decode.decodeValue Decode.string value of
                Ok units ->
                    ( { model | units = units }
                    , pushValues model.theme units
                    )

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


pushValues : String -> String -> Cmd Msg
pushValues theme units =
    Phone.sendPhoneToWatch (ProvideTheme theme units)
