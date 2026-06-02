module Companion.GeneratedPreferences exposing
    ( configurationResponseDecoder
    , decodeConfigurationFlags
    , decodeConfigurationSaved
    , onConfiguration
    , preferencesErrorToString
    )

{-| Generated bridge for Pebble companion preferences.

This module is derived from the project's `Pebble.Companion.Preferences`
schema. Edit that schema instead of this file.
-}

import CompanionPreferences as PreferencesSchema
import Json.Decode as Decode
import Pebble.Companion.Configuration as Configuration
import Pebble.Companion.Phone as RawBridge
import Pebble.Companion.Preferences as Preferences


{-| Subscribe to configuration responses from the Pebble mobile app.

    subscriptions : Model -> Sub Msg
    subscriptions _ =
        GeneratedPreferences.onConfiguration PreferencesSaved

`PreferencesSaved` receives a `Result String PreferencesSchema.Model`.
-}
onConfiguration toMsg =
    Configuration.onClosed <|
        \maybeResponse ->
            toMsg <|
                (Preferences.decodeResponse PreferencesSchema.settings maybeResponse
                    |> Result.mapError preferencesErrorToString)


{-| Decode a raw bridge event produced when the configuration page closes.

    update msg model =
        case msg of
            FromBridge raw ->
                case GeneratedPreferences.decodeConfigurationSaved raw of
                    Ok saved ->
                        -- Store or send `saved`.
                        ( { model | settings = saved }, Cmd.none )

                    Err message ->
                        ( { model | error = Just message }, Cmd.none )

Prefer `onConfiguration` when wiring subscriptions directly.
-}
decodeConfigurationSaved value =
    Decode.decodeValue configurationResponseDecoder value
        |> Result.mapError Decode.errorToString
        |> Result.andThen
            (\response ->
                Preferences.decodeResponse PreferencesSchema.settings response
                    |> Result.mapError preferencesErrorToString
            )


{-| Decode initial companion app flags into previously saved preferences.

    init : Flags -> ( Model, Cmd Msg )
    init flags =
        case GeneratedPreferences.decodeConfigurationFlags flags of
            Ok (Just saved) ->
                ( { initialModel | settings = saved }, Cmd.none )

            Ok Nothing ->
                ( initialModel, Cmd.none )

            Err message ->
                ( { initialModel | error = Just message }, Cmd.none )

The result is `Nothing` when no saved configuration is available yet.
-}
decodeConfigurationFlags value =
    Decode.decodeValue configurationFlagsDecoder value
        |> Result.mapError Decode.errorToString
        |> Result.andThen
            (\response ->
                case response of
                    Just saved ->
                        Preferences.decodeResponse PreferencesSchema.settings (Just saved)
                            |> Result.map Just
                            |> Result.mapError preferencesErrorToString

                    Nothing ->
                        Ok Nothing
            )


{-| Decode the optional `configurationResponse` string from companion flags.

Most apps should use `decodeConfigurationFlags`, which also applies the
generated typed preferences schema.
-}
configurationFlagsDecoder =
    Decode.field "configurationResponse" (Decode.nullable Decode.string)


{-| Decode the raw `configuration.closed` bridge event response.

Most apps should use `decodeConfigurationSaved`, which also converts the
response into typed preferences.
-}
configurationResponseDecoder =
    Decode.field "event" Decode.string
        |> Decode.andThen
            (\event ->
                if event == "configuration.closed" then
                    Decode.at [ "payload", "response" ] (Decode.nullable Decode.string)

                else
                    Decode.fail ("Unexpected bridge event: " ++ event)
            )


{-| Convert typed preference decode errors into user-facing strings.

    message =
        GeneratedPreferences.preferencesErrorToString error

This is already used by `decodeConfigurationSaved` and
`decodeConfigurationFlags`.
-}
preferencesErrorToString error =
    case error of
        Preferences.InvalidJson message ->
            message

        Preferences.MissingResponse ->
            "Configuration closed without a response"
