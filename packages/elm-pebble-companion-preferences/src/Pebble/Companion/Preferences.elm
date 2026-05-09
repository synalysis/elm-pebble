module Pebble.Companion.Preferences
    exposing
        ( ChoiceOption
        , Color
        , Control
        , Error(..)
        , Field
        , Schema
        , Section
        , black
        , blue
        , choice
        , choiceOption
        , color
        , decodeResponse
        , decodeString
        , decoder
        , field
        , green
        , number
        , schema
        , section
        , sendToWatch
        , slider
        , text
        , toggle
        , white
        , yellow
        )

{-| Typed declarations for Pebble companion preference pages.

The same schema describes the generated, Slate-like configuration page and the
decoder used when Pebble returns saved values.

    type alias Settings =
        { showDate : Bool
        , units : Units
        }

    type Units
        = Celsius
        | Fahrenheit

    settings : Schema Settings
    settings =
        schema "Settings" Settings
            |> section "Display"
                (\s ->
                    s
                        |> field "showDate" (toggle "Show date" True)
                        |> field "units"
                            (choice "Units"
                                [ choiceOption Celsius "c" "Celsius"
                                , choiceOption Fahrenheit "f" "Fahrenheit"
                                ]
                            )
                )

# Schemas
@docs Schema, Error, schema, section, field, decoder, decodeString, decodeResponse

# Controls
@docs Control, Field, Section, toggle, text, number, slider, color, choice, ChoiceOption, choiceOption, sendToWatch

# Colors
@docs Color, black, white, green, blue, yellow

-}

import Json.Decode as Decode exposing (Decoder)


{-| Opaque preference schema that decodes to `settings`.
-}
type Schema settings
    = Schema (SchemaData settings)


type alias SchemaData settings =
    { title : String
    , sections : List Section
    , currentSection : Maybe String
    , decoder : Decoder settings
    }


{-| A visual group of fields.
-}
type alias Section =
    { title : String
    , fields : List FieldDefinition
    }


{-| A typed field. The generator uses the definition; Elm code uses the decoder.
-}
type Field value
    = Field FieldDefinition (Decoder value)


type alias FieldDefinition =
    { id : String
    , label : String
    , control : ControlDefinition
    }


{-| A typed control for a single field.
-}
type Control value
    = Control ControlDefinition (Decoder value)


type alias ControlDefinition =
    { label : String
    , kind : ControlKind
    , sendToWatch : Maybe String
    }


type ControlKind
    = ToggleControl Bool
    | TextControl String
    | NumberControl Float
    | SliderControl Float Float Float Float
    | ColorControl Color
    | ChoiceControl (List ChoiceDefinition)


type alias ChoiceDefinition =
    { value : String
    , label : String
    }


{-| A choice option mapping an encoded webview value to a real Elm value.
-}
type ChoiceOption value
    = ChoiceOption value ChoiceDefinition


{-| Pebble configuration color value encoded as a CSS hex string.
-}
type alias Color =
    String


{-| Decode errors from a saved configuration payload.
-}
type Error
    = InvalidJson String
    | MissingResponse


{-| Start a schema with a record or custom type constructor.
-}
schema : String -> settings -> Schema settings
schema title constructor =
    Schema
        { title = title
        , sections = []
        , currentSection = Nothing
        , decoder = Decode.succeed constructor
        }


{-| Add a visual section. Fields added inside the callback are grouped under the section title.
-}
section : String -> (Schema partial -> Schema next) -> Schema partial -> Schema next
section title build (Schema data) =
    let
        start =
            Schema { data | currentSection = Just title, sections = data.sections ++ [ Section title [] ] }

        (Schema next) =
            build start
    in
    Schema { next | currentSection = data.currentSection }


{-| Add a typed field to the schema.

Fields are decoded in the order they are added, so this works naturally with
Elm record constructors and normal pipeline style.
-}
field : String -> Control value -> Schema (value -> next) -> Schema next
field id (Control definition valueDecoder) (Schema data) =
    let
        fieldDefinition =
            { id = id
            , label = definition.label
            , control = definition
            }
    in
    Schema
        { title = data.title
        , sections = addField data.currentSection fieldDefinition data.sections
        , currentSection = data.currentSection
        , decoder = Decode.map2 (<|) data.decoder (Decode.field id valueDecoder)
        }


{-| Decode the saved Pebble webview payload.
-}
decoder : Schema settings -> Decoder settings
decoder (Schema data) =
    data.decoder


{-| Decode a saved JSON string into typed settings.
-}
decodeString : Schema settings -> String -> Result Error settings
decodeString preferences payload =
    Decode.decodeString (decoder preferences) payload
        |> Result.mapError (Decode.errorToString >> InvalidJson)


{-| Decode Pebble's optional `webviewclosed` response into typed settings.
-}
decodeResponse : Schema settings -> Maybe String -> Result Error settings
decodeResponse preferences response =
    case response of
        Just payload ->
            decodeString preferences payload

        Nothing ->
            Err MissingResponse


{-| A boolean toggle.
-}
toggle : String -> Bool -> Control Bool
toggle label default =
    Control { label = label, kind = ToggleControl default, sendToWatch = Nothing } Decode.bool


{-| A text input.
-}
text : String -> String -> Control String
text label default =
    Control { label = label, kind = TextControl default, sendToWatch = Nothing } Decode.string


{-| A numeric input.
-}
number : String -> Float -> Control Float
number label default =
    Control { label = label, kind = NumberControl default, sendToWatch = Nothing } Decode.float


{-| A slider with minimum, maximum, step, and default values.
-}
slider : String -> { min : Float, max : Float, step : Float, default : Float } -> Control Float
slider label options =
    Control
        { label = label
        , kind = SliderControl options.min options.max options.step options.default
        , sendToWatch = Nothing
        }
        Decode.float


{-| A color picker encoded as a CSS hex string.
-}
color : String -> Color -> Control Color
color label default =
    Control { label = label, kind = ColorControl default, sendToWatch = Nothing } Decode.string


{-| A select/radio-style choice that decodes to real Elm values.
-}
choice : String -> List (ChoiceOption value) -> Control value
choice label options =
    let
        definitions =
            List.map (\(ChoiceOption _ definition) -> definition) options

        decodeOption encoded =
            options
                |> List.filter (\(ChoiceOption _ definition) -> definition.value == encoded)
                |> List.head
                |> Maybe.map (\(ChoiceOption value _) -> Decode.succeed value)
                |> Maybe.withDefault (Decode.fail ("Unknown preference option: " ++ encoded))
    in
    Control { label = label, kind = ChoiceControl definitions, sendToWatch = Nothing } (Decode.string |> Decode.andThen decodeOption)


{-| Declare the phone-to-watch message constructor emitted when this preference is saved.

This is debugger/build metadata; the typed decoder still determines the Elm value
seen by the companion app.
-}
sendToWatch : String -> Control value -> Control value
sendToWatch constructor (Control definition valueDecoder) =
    Control { definition | sendToWatch = Just constructor } valueDecoder


{-| Define one encoded choice value and the Elm value it represents.
-}
choiceOption : value -> String -> String -> ChoiceOption value
choiceOption value encoded label =
    ChoiceOption value { value = encoded, label = label }


{-| Black color swatch.
-}
black : Color
black =
    "#000000"


{-| White color swatch.
-}
white : Color
white =
    "#FFFFFF"


{-| Green color swatch.
-}
green : Color
green =
    "#55AA55"


{-| Blue color swatch.
-}
blue : Color
blue =
    "#5555FF"


{-| Yellow color swatch.
-}
yellow : Color
yellow =
    "#FFFF55"


addField : Maybe String -> FieldDefinition -> List Section -> List Section
addField current fieldDefinition sections =
    case current of
        Just title ->
            case List.reverse sections of
                [] ->
                    [ Section title [ fieldDefinition ] ]

                lastSection :: previous ->
                    if lastSection.title == title then
                        List.reverse ({ lastSection | fields = lastSection.fields ++ [ fieldDefinition ] } :: previous)

                    else
                        sections ++ [ Section title [ fieldDefinition ] ]

        Nothing ->
            sections ++ [ Section "" [ fieldDefinition ] ]
