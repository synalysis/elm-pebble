defmodule Ide.CompanionProtocolGeneratorTest do
  use ExUnit.Case, async: true

  alias Ide.CompanionProtocolGenerator

  @types """
  module Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), TutorialColor(..), WatchToPhone(..))

  type Location
      = CurrentLocation
      | Berlin
      | Zurich

  type Temperature
      = Celsius Int
      | Fahrenheit Int

  type TutorialColor
      = Black
      | White

  type WatchToPhone
      = RequestWeather Location
      | RequestUpdate

  type PhoneToWatch
      = ProvideTemperature Temperature
      | SetBackgroundColor TutorialColor
      | SetShowDate Bool
      | SetLabel String
  """

  test "generates single-field enum watch-to-phone decode without nested Decode.field" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-enum-w2p-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.write!(types, @types)

      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)

      generated_internal = File.read!(internal)

      assert generated_internal =~
               "Decode.decodeValue (Decode.field \"request_weather_field1\" Decode.int) value"

      refute generated_internal =~
               "Decode.field \"request_weather_field1\" Decode.field \"request_weather_field1\""
    after
      File.rm_rf(tmp)
    end
  end

  test "extracts generic ADT schema without app-specific query data" do
    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(@types)

    assert schema.enums == %{
             "Location" => ["CurrentLocation", "Berlin", "Zurich"],
             "TutorialColor" => ["Black", "White"]
           }

    assert Enum.map(schema.payload_unions["Temperature"], & &1.name) == ["Celsius", "Fahrenheit"]

    assert [
             %{name: "RequestWeather", tag: 2, fields: [request_field]},
             %{name: "RequestUpdate", tag: 3, fields: []}
           ] = schema.watch_to_phone

    assert request_field.wire_type == {:enum, "Location"}

    assert Enum.map(schema.phone_to_watch, & &1.name) == [
             "ProvideTemperature",
             "SetBackgroundColor",
             "SetShowDate",
             "SetLabel"
           ]

    refute inspect(schema) =~ "latitude"
  end

  test "generates C and JS from the extracted schema" do
    tmp =
      Path.join(System.tmp_dir!(), "elm-pebble-protocol-#{System.unique_integer([:positive])}")

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.write!(types, @types)

      assert :ok =
               CompanionProtocolGenerator.generate(types, header, source, js,
                 runtime_tags: %{
                   "Temperature" => %{"Celsius" => 41, "Fahrenheit" => 42},
                   "TutorialColor" => %{"Black" => 51, "White" => 52}
                 }
               )

      assert File.read!(header) =~ "COMPANION_PROTOCOL_ENUM_LOCATION_CURRENT_LOCATION 1"
      assert File.read!(header) =~ "COMPANION_PROTOCOL_TAG_REQUEST_WEATHER 2"
      assert File.read!(source) =~ "companion_protocol_dispatch_phone_to_watch"
      assert File.read!(source) =~ "ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET"
      assert File.read!(source) =~ "companion_protocol_new_union_value"
      assert File.read!(source) =~ "companion_protocol_new_phone_to_watch_message"
      assert File.read!(source) =~ "*out = decoder->message;"

      assert File.read!(source) =~
               "out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PROVIDE_TEMPERATURE"

      refute File.read!(source) =~
               "out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PROVIDE_TEMPERATURE;\n      *out = decoder->message;"

      assert File.read!(source) =~ "case 1: return 41;"
      assert File.read!(source) =~ "case 2: return 52;"
      refute File.read!(source) =~ "tag + 1"
      assert File.read!(source) =~ "decoder->message.int_fields[0] = 1;"
      assert File.read!(source) =~ "decoder->message.union_value_fields[0] = 0;"

      assert File.read!(source) =~
               "CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out)"

      refute File.read!(source) =~ "const CompanionProtocolPhoneToWatchDecoder *decoder"
      assert File.read!(header) =~ "COMPANION_PROTOCOL_KEY_PROVIDE_TEMPERATURE_FIELD1_TAG"
      assert File.read!(header) =~ "COMPANION_PROTOCOL_KEY_PROVIDE_TEMPERATURE_FIELD1_VALUE"
      assert File.read!(header) =~ "ELMC_COMPANION_SIMULATOR_WEATHER 1"
      assert File.read!(header) =~ "ELMC_COMPANION_SIMULATOR_WEATHER_MODE_TEMPERATURE_ONLY 1"
      assert File.read!(header) =~ "ELMC_COMPANION_PROTOCOL_HAS_UNION_PAYLOADS 1"
      assert File.read!(js) =~ "decodeWatchToPhonePayload"
      assert File.read!(js) =~ "locationNameForCode"
      assert File.read!(js) =~ ~s/payload[String(constants.KEY_MESSAGE_TAG)] = 201/
    after
      File.rm_rf(tmp)
    end
  end

  test "omits unused protocol payload storage from generated C structs" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-compact-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = ProvidePiece Int Int Int Int
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)

      generated_header = File.read!(header)
      generated_source = File.read!(source)

      assert generated_header =~ "int32_t int_fields[COMPANION_PROTOCOL_MAX_FIELDS]"
      refute generated_header =~ "string_fields"
      refute generated_header =~ "bool_fields"
      refute generated_header =~ "union_value_fields"
      refute generated_header =~ "saw_union_value_fields"
      refute generated_source =~ "saw_union_value_fields"
    after
      File.rm_rf(tmp)
    end
  end

  test "extracts List Int fields with indexed AppMessage keys" do
    types = """
    module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

    type WatchToPhone
        = RequestFigure

    type PhoneToWatch
        = ProvidePiece Int (List Int)
    """

    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(types)

    assert [%{name: "ProvidePiece", fields: fields}] = schema.phone_to_watch
    assert [%{wire_type: {:list, :int}, key: "provide_piece_field2"}] = Enum.drop(fields, 1)

    assert schema.key_ids["provide_piece_field2_count"]
    assert schema.key_ids["provide_piece_field2_0"]
    assert schema.key_ids["provide_piece_field2_15"]
    refute Map.has_key?(schema.key_ids, "provide_piece_field2_16")
  end

  test "generates list int wire helpers in C, JS, and Elm" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-list-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = ProvidePiece Int (List Int)
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)
      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)

      generated_header = File.read!(header)
      generated_source = File.read!(source)
      generated_js = File.read!(js)
      generated_internal = File.read!(internal)

      assert generated_header =~ "COMPANION_PROTOCOL_LIST_MAX_ELEMENTS 16"
      assert generated_header =~ "list_counts[COMPANION_PROTOCOL_MAX_FIELDS]"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_PROVIDE_PIECE_FIELD2_COUNT"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_PROVIDE_PIECE_FIELD2_0"

      assert generated_source =~ "companion_protocol_decode_list_wire_int"
      assert generated_source =~ "elmc_list_from_int_array(message->list_values[1]"
      refute generated_source =~ "elmc_pebble_dispatch_tag_int_values(app"

      assert generated_js =~ "encodeListIntField"
      assert generated_internal =~ "decodeListInt"
      assert generated_internal =~ "encodeListInt"
      assert generated_internal =~ "++ encodeListInt \"provide_piece_field2\" field2"
    after
      File.rm_rf(tmp)
    end
  end

  test "generates record wire slots and C builders from type aliases" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-record-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), Point, WatchToPhone(..))

      type alias Point =
          { x : Int, y : Int }

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = SetOrigin Point
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)
      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)

      generated_header = File.read!(header)
      generated_source = File.read!(source)
      generated_js = File.read!(js)
      generated_internal = File.read!(internal)

      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_ORIGIN_FIELD1_X"
      assert generated_header =~ "int32_t wire_set_origin_field1_x;"
      assert generated_header =~ "bool saw_wire_set_origin_field1_x;"
      assert generated_source =~ "companion_protocol_build_set_origin_field1"
      assert generated_source =~ "elmc_record_new_take"
      assert generated_source =~ ~s<const char *v_names[] = { "x", "y" };>

      assert generated_js =~
               "payload[String(constants.KEY_SET_ORIGIN_FIELD1_X)] = value && value.x"

      assert generated_internal =~ "decodePoint : String -> Decode.Decoder Point"

      assert generated_internal =~
               "encodePoint : String -> Point -> List ( String, Encode.Value )"

      assert generated_internal =~ "++ encodePoint \"set_origin_field1\" field1"
    after
      File.rm_rf(tmp)
    end
  end

  test "generates list of records and dict string value wire slots" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-composite-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (Labels, PhoneToWatch(..), Point, WatchToPhone(..))

      type alias Point =
          { x : Int, y : Int }

      type alias Labels =
          { labels : Dict String Int }

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = ProvidePoints (List Point)
          | SetLabels (Dict String Int)
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)
      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)

      generated_header = File.read!(header)
      generated_source = File.read!(source)
      generated_js = File.read!(js)
      generated_internal = File.read!(internal)

      assert generated_header =~ "COMPANION_PROTOCOL_KEY_PROVIDE_POINTS_FIELD1_COUNT"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_PROVIDE_POINTS_FIELD1_0_X"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_LABELS_FIELD1_KEY_0"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_LABELS_FIELD1_VAL_0"

      assert generated_source =~ "elmc_list_from_values_take"
      assert generated_source =~ "elmc_dict_from_list"
      assert generated_source =~ "elmc_tuple2"

      assert generated_js =~ "provide_points_field1_items"
      assert generated_js =~ "set_labels_field1_entries"
      assert generated_internal =~ "encodeListBy \"provide_points_field1\""
      assert generated_internal =~ "encodeDictStringBy \"set_labels_field1\""
    after
      File.rm_rf(tmp)
    end
  end

  test "generates variant-specific wire slots for multi-argument unions" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-union-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), Shape(..), WatchToPhone(..))

      type Shape
          = None
          | Circle Int
          | Label String Int

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = SetShape Shape
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)
      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)

      generated_header = File.read!(header)
      generated_source = File.read!(source)
      generated_internal = File.read!(internal)

      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_SHAPE_FIELD1_TAG"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_SHAPE_FIELD1_LABEL_ARG1"
      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_SHAPE_FIELD1_LABEL_ARG2"
      assert generated_source =~ "companion_protocol_build_set_shape_field1"
      assert generated_source =~ "case 3:"
      assert generated_internal =~ "decodeShapeWire : String -> Decode.Decoder Shape"

      assert generated_internal =~
               "encodeShapeWire : String -> Shape -> List ( String, Encode.Value )"

      assert generated_internal =~ "++ encodeShapeWire \"set_shape_field1\" field1"
    after
      File.rm_rf(tmp)
    end
  end

  test "generates Elm internal helpers from the extracted schema" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-elm-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.write!(types, @types)

      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)
      generated = File.read!(internal)

      assert generated =~ "Generated wire encoding and decoding helpers"
      assert generated =~ "encodeLocationCode : Location -> Int"
      assert generated =~ "decodeLocationCode : Int -> Maybe Location"
      assert generated =~ "encodeTemperatureTag : Temperature -> Int"
      assert generated =~ "encodeTemperatureValue : Temperature -> Int"
      assert generated =~ "decodeTemperature : Int -> Int -> Maybe Temperature"
      assert generated =~ "encodeTutorialColorCode : TutorialColor -> Int"
      assert generated =~ "( \"set_show_date_field1\", Encode.int (if field1 then 1 else 2) )"
      assert generated =~ "                    3 ->\n                        Ok RequestUpdate"
      assert generated =~ "watchToPhoneTag : WatchToPhone -> Int"
      refute generated =~ "locationWeatherQuery"
      refute generated =~ ", location"
    after
      File.rm_rf(tmp)
    end
  end
end
