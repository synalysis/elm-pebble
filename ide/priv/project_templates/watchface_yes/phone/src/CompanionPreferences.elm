module CompanionPreferences exposing (Settings, preferencesDefaults, settings)

import Pebble.Companion.Preferences as Preferences


type alias Settings =
    {}


preferencesDefaults : Settings
preferencesDefaults =
    {}


settings : Preferences.Schema Settings
settings =
    Preferences.schema "YES Watchface" preferencesDefaults
