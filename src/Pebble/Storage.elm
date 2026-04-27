module Pebble.Storage exposing
    ( StorageKey
    , StorageValue
    , StorageCmd(..)
    , save
    , load
    , remove
    , saveJson
    , loadJson
    , saveInt
    , loadInt
    , saveBool
    , loadBool
    , clear
    )

{-| Persistent storage for Pebble applications.

# Types
@docs StorageKey, StorageValue, StorageCmd

# Basic Operations
@docs save, load, remove, clear

# Typed Operations
@docs saveJson, loadJson, saveInt, loadInt, saveBool, loadBool

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


-- TYPES

{-| A key for storing data.
-}
type alias StorageKey =
    String


{-| A value that can be stored.
-}
type StorageValue
    = StringValue String
    | IntValue Int
    | BoolValue Bool
    | JsonValue Encode.Value


{-| Commands for storage operations.
-}
type StorageCmd msg
    = Save StorageKey StorageValue (Result String () -> msg)
    | Load StorageKey (Result String StorageValue -> msg)
    | Remove StorageKey (Result String () -> msg)
    | Clear (Result String () -> msg)


-- BASIC OPERATIONS

{-| Save a string value.

    Storage.save "username" (StringValue "alice") SaveCompleted

-}
save : StorageKey -> StorageValue -> (Result String () -> msg) -> StorageCmd msg
save key value toMsg =
    Save key value toMsg


{-| Load a value by key.

    Storage.load "username" UsernameLoaded

-}
load : StorageKey -> (Result String StorageValue -> msg) -> StorageCmd msg
load key toMsg =
    Load key toMsg


{-| Remove a value by key.

    Storage.remove "username" RemoveCompleted

-}
remove : StorageKey -> (Result String () -> msg) -> StorageCmd msg
remove key toMsg =
    Remove key toMsg


{-| Clear all stored data.

    Storage.clear ClearCompleted

-}
clear : (Result String () -> msg) -> StorageCmd msg
clear toMsg =
    Clear toMsg


-- TYPED OPERATIONS

{-| Save JSON-encodable data.

    type alias UserSettings = { theme : String, notifications : Bool }
    
    saveJson "settings" 
        (Encode.object 
            [ ("theme", Encode.string settings.theme)
            , ("notifications", Encode.bool settings.notifications)
            ]
        ) 
        SaveCompleted

-}
saveJson : StorageKey -> Encode.Value -> (Result String () -> msg) -> StorageCmd msg
saveJson key value toMsg =
    Save key (JsonValue value) toMsg


{-| Load and decode JSON data.

    type alias UserSettings = { theme : String, notifications : Bool }
    
    settingsDecoder : Decoder UserSettings
    settingsDecoder =
        Decode.map2 UserSettings
            (Decode.field "theme" Decode.string)
            (Decode.field "notifications" Decode.bool)
    
    loadJson "settings" settingsDecoder SettingsLoaded

-}
loadJson : StorageKey -> Decoder a -> (Result String a -> msg) -> StorageCmd msg
loadJson key decoder toMsg =
    Load key (\result ->
        case result of
            Err error ->
                toMsg (Err error)
            
            Ok (JsonValue jsonValue) ->
                case Decode.decodeValue decoder jsonValue of
                    Ok decoded ->
                        toMsg (Ok decoded)
                    
                    Err decodeError ->
                        toMsg (Err (Decode.errorToString decodeError))
            
            Ok _ ->
                toMsg (Err "Expected JSON value but got different type")
    )


{-| Save an integer value.

    saveInt "high_score" 12500 SaveCompleted

-}
saveInt : StorageKey -> Int -> (Result String () -> msg) -> StorageCmd msg
saveInt key value toMsg =
    Save key (IntValue value) toMsg


{-| Load an integer value.

    loadInt "high_score" HighScoreLoaded

-}
loadInt : StorageKey -> (Result String Int -> msg) -> StorageCmd msg
loadInt key toMsg =
    Load key (\result ->
        case result of
            Err error ->
                toMsg (Err error)
            
            Ok (IntValue value) ->
                toMsg (Ok value)
            
            Ok _ ->
                toMsg (Err "Expected integer value but got different type")
    )


{-| Save a boolean value.

    saveBool "notifications_enabled" True SaveCompleted

-}
saveBool : StorageKey -> Bool -> (Result String () -> msg) -> StorageCmd msg
saveBool key value toMsg =
    Save key (BoolValue value) toMsg


{-| Load a boolean value.

    loadBool "notifications_enabled" NotificationsLoaded

-}
loadBool : StorageKey -> (Result String Bool -> msg) -> StorageCmd msg
loadBool key toMsg =
    Load key (\result ->
        case result of
            Err error ->
                toMsg (Err error)
            
            Ok (BoolValue value) ->
                toMsg (Ok value)
            
            Ok _ ->
                toMsg (Err "Expected boolean value but got different type")
    ) 