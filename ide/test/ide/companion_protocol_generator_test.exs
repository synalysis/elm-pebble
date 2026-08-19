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

  test "generates composite watch-to-phone decode without nested Decode.field" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-composite-w2p-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    internal = Path.join(tmp, "Companion/Internal.elm")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (Color(..), Measure(..), PhoneToWatch(..), Point, WatchToPhone(..))

      type Color
          = Red
          | Green

      type Measure
          = Liters Int
          | Pounds Int

      type alias Point =
          { x : Int, y : Int }

      type WatchToPhone
          = SendColor Color
          | SendMeasure Measure
          | SendPoint Point
          | SendCounts (List Int)

      type PhoneToWatch
          = Pong
      """)

      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types, internal)

      generated_internal = File.read!(internal)

      assert generated_internal =~
               "Decode.decodeValue (Decode.field \"send_color_field1\" Decode.int) value"

      assert generated_internal =~ "decodeMeasureLegacyWire : String -> Decode.Decoder Measure"

      assert generated_internal =~
               "Decode.decodeValue (decodeMeasureLegacyWire \"send_measure_field1\") value"

      refute generated_internal =~ "decodeMeasureWatchScalar"
      refute generated_internal =~ "decodeMeasureWire"

      assert generated_internal =~
               "Decode.decodeValue (decodePoint \"send_point_field1\") value"

      assert generated_internal =~
               "Decode.decodeValue (decodeListInt \"send_counts_field1\") value"

      refute generated_internal =~
               "Decode.field \"send_point_field1\" decodePoint"

      refute generated_internal =~
               "Decode.field \"send_counts_field1\" decodeListInt"

      assert generated_internal =~ "SendPoint field1 ->\n            0"
      assert generated_internal =~ "SendCounts field1 ->\n            0"
      assert generated_internal =~ "SendMeasure field1 ->\n            encodeMeasureTag field1"
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
      assert generated_source =~ "companion_protocol_box_int("
      assert generated_source =~ "companion_protocol_tuple2_take("
      refute generated_source =~ "companion_protocol_box_bool("
      refute generated_source =~ "companion_protocol_box_string("
      refute generated_source =~ "companion_protocol_box_int_list("
      # Tag-only WatchToPhone has no int payload writes — omit the encode helper.
      refute generated_source =~ "companion_protocol_value_int("
    after
      File.rm_rf(tmp)
    end
  end

  test "emits companion_protocol_value_int only when WatchToPhone carries int fields" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-value-int-#{System.unique_integer([:positive])}"
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
          = SendCount Int

      type PhoneToWatch
          = Ack
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)
      generated_source = File.read!(source)
      assert generated_source =~ "companion_protocol_value_int("
      assert generated_source =~ "dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_COUNT_FIELD1"
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
      # ProvidePiece: tag + Int + (count + 16 list slots) = 19 keys → 1 + 19*11 + 32 = 242
      assert generated_header =~ "ELMC_PEBBLE_APP_MESSAGE_INBOX_SIZE_REQUIRED 242"
      assert generated_header =~ "ELMC_PEBBLE_APP_MESSAGE_OUTBOX_SIZE_REQUIRED 636"

      assert generated_source =~ "companion_protocol_decode_list_wire_int"
      assert generated_source =~ "companion_protocol_box_int_list(message->list_values[1]"
      refute generated_source =~ "elmc_pebble_dispatch_tag_int_values(app"

      assert generated_js =~ "encodeListIntField"
      assert generated_internal =~ "decodeListInt"
      assert generated_internal =~ "encodeListInt"
      assert generated_internal =~ "++ encodeListInt \"provide_piece_field2\" field2"
      assert generated_js =~ "wirePhoneToWatchFromElmPayload"
      assert generated_js =~ "elmPayloadListInt"
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
      assert generated_source =~ "elmc_record_new_take(&v_out"
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

  test "resolves Dict.Dict String Int payload fields for phone-to-watch encode" do
    types = """
    module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

    type WatchToPhone
        = RequestFigure

    type PhoneToWatch
        = PushLabels (Dict.Dict String Int)
    """

    assert {:ok, schema} = CompanionProtocolGenerator.schema_from_source(types)

    [%{fields: [field]}] = schema.phone_to_watch
    assert field.wire_type == {:dict, :int}

    tmp = Path.join(System.tmp_dir!(), "elm-pebble-protocol-dict-#{System.unique_integer([:positive])}")
    types_path = Path.join(tmp, "Types.elm")
    internal = Path.join(tmp, "Companion/Internal.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")

    try do
      File.mkdir_p!(Path.dirname(internal))
      File.write!(types_path, types)
      assert :ok = CompanionProtocolGenerator.generate(types_path, header, source, js)
      assert :ok = CompanionProtocolGenerator.generate_elm_internal(types_path, internal)

      generated_internal = File.read!(internal)
      generated_source = File.read!(source)

      assert generated_internal =~ "encodeDictStringBy \"push_labels_field1\""
      refute generated_internal =~ ~s|"push_labels_field1", Encode.int field1|
      assert generated_source =~ "COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1_COUNT"
      refute generated_source =~ "COMPANION_PROTOCOL_KEY_PUSH_LABELS_FIELD1)"

      # elmc_tuple2_take releases *out when non-NULL; scratch must be zeroed.
      assert generated_source =~ ~r/ElmcValue \*\w+_pairs\[\d+\] = \{0\};/
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
      assert generated_source =~ "companion_protocol_box_string("
      assert generated_source =~ "case 3:"
      assert generated_internal =~ "decodeShapeWire : String -> Decode.Decoder Shape"

      assert generated_internal =~
               "encodeShapeWire : String -> Shape -> List ( String, Encode.Value )"

      assert generated_internal =~ "++ encodeShapeWire \"set_shape_field1\" field1"
    after
      File.rm_rf(tmp)
    end
  end

  test "dispatches tag-only phone-to-watch messages as bare union tags" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-pong-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    source = Path.join(tmp, "generated/companion_protocol.c")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

      type WatchToPhone
          = Ping

      type PhoneToWatch
          = Pong
          | EchoColor Int
      """)

      assert :ok =
               CompanionProtocolGenerator.generate(
                 types,
                 Path.join(tmp, "generated/companion_protocol.h"),
                 source,
                 Path.join(tmp, "pkjs/companion-protocol.js")
               )

      generated_source = File.read!(source)

      assert generated_source =~ "COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PONG"
      assert generated_source =~ "ElmcValue *payload = companion_protocol_box_int(1);"
      assert generated_source =~
               "elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, payload);"

      assert generated_source =~ "elmc_release(payload);"

      refute generated_source =~
               "COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_PONG: {\n          if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;\n      return elmc_pebble_dispatch_tag_int_values"
    after
      File.rm_rf(tmp)
    end
  end

  test "writes legacy union watch-to-phone scalar wire with zero value slot" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-measure-w2p-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    source = Path.join(tmp, "generated/companion_protocol.c")

    try do
      File.mkdir_p!(Path.dirname(types))

      File.write!(types, """
      module Companion.Types exposing (Measure(..), PhoneToWatch(..), WatchToPhone(..))

      type Measure
          = Liters Int
          | Pounds Int

      type WatchToPhone
          = SendMeasure Measure

      type PhoneToWatch
          = Pong
      """)

      assert :ok =
               CompanionProtocolGenerator.generate(
                 types,
                 Path.join(tmp, "generated/companion_protocol.h"),
                 source,
                 Path.join(tmp, "pkjs/companion-protocol.js")
               )

      generated_source = File.read!(source)

      assert generated_source =~
               "dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG, value);"

      assert generated_source =~
               "dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE, 0);"
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

  test "generates watch-to-phone value encode for every payload shape" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-w2p-value-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "companion_protocol.h")
    source = Path.join(tmp, "companion_protocol.c")
    js = Path.join(tmp, "companion-protocol.js")

    try do
      File.mkdir_p!(tmp)

      File.write!(types, """
      module Companion.Types exposing (Color(..), Measure(..), PhoneToWatch(..), Point, WatchToPhone(..))

      type Color
          = Red
          | Green

      type Measure
          = Liters Int
          | Pounds Int

      type alias Point =
          { x : Int, y : Int }

      type WatchToPhone
          = Ping
          | SendColor Color
          | SendMeasure Measure
          | SendPoint Point
          | SendCounts (List Int)

      type PhoneToWatch
          = Pong
      """)

      runtime_tags = %{
        "WatchToPhone" => %{
          "Ping" => 11,
          "SendColor" => 12,
          "SendMeasure" => 13,
          "SendPoint" => 14,
          "SendCounts" => 15
        },
        "Color" => %{"Red" => 21, "Green" => 22},
        "Measure" => %{"Liters" => 31, "Pounds" => 32}
      }

      assert :ok =
               CompanionProtocolGenerator.generate(types, header, source, js,
                 runtime_tags: runtime_tags
               )

      generated_h = File.read!(header)
      generated_c = File.read!(source)

      assert generated_h =~
               "bool companion_protocol_encode_watch_to_phone_value(DictionaryIterator *iter, ElmcValue *message);"

      # Runtime constructor tags select the case; wire codes go on the wire.
      assert generated_c =~ "switch ((int32_t)elmc_union_tag_as_int(message)) {"
      assert generated_c =~ "case 11: {"
      assert generated_c =~ "case 15: {"
      assert generated_c =~ "static int32_t companion_protocol_wire_code_COLOR(int32_t runtime_tag)"
      assert generated_c =~ "case 21: return 1;"
      assert generated_c =~ "case 32: return 2;"

      # Enum payload.
      assert generated_c =~
               "dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_COLOR_FIELD1, companion_protocol_wire_code_COLOR((int32_t)elmc_union_tag_as_int("

      # Legacy union payload writes both tag and value.
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_TAG"

      assert generated_c =~
               "dict_write_int32(iter, COMPANION_PROTOCOL_KEY_SEND_MEASURE_FIELD1_VALUE, (int32_t)elmc_union_payload_int("

      # Record payload writes every field by index (nameless records from plan).
      assert generated_c =~ "elmc_record_get_index("
      refute generated_c =~ ~r/elmc_record_get\([^,]+,\s*"/
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_X"
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_POINT_FIELD1_Y"

      # List payload writes an offset count plus offset elements.
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_COUNT"
      assert generated_c =~ "elmc_list_nth_int_default("
      assert generated_c =~ "COMPANION_PROTOCOL_KEY_SEND_COUNTS_FIELD1_15"

      # The legacy scalar entry point still exists for tag/value callers.
      assert generated_c =~
               "bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value)"
    after
      File.rm_rf(tmp)
    end
  end

  test "wirePhoneToWatchFromElmPayload includes tagged union phone-to-watch messages" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-yes-js-#{System.unique_integer([:positive])}"
      )

    types =
      Path.expand("../../priv/project_templates/watchface_yes/protocol/src/Companion/Types.elm", __DIR__)

    header = Path.join(tmp, "companion_protocol.h")
    source = Path.join(tmp, "companion_protocol.c")
    js = Path.join(tmp, "companion-protocol.js")

    try do
      File.mkdir_p!(tmp)
      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)
      generated_js = File.read!(js)
      generated_c = File.read!(source)

      # Every phone->watch tag round-trips: the wire helper renames Elm wire keys
      # to AppMessage ids instead of re-deriving values per constructor.
      assert generated_js =~ "var PHONE_TO_WATCH_TAGS = {"
      assert generated_js =~ "  205: true,"
      assert generated_js =~ "  206: true,"
      assert generated_js =~ "  209: true,"
      assert generated_js =~ "PHONE_TO_WATCH_TAGS[tag] !== true"
      assert generated_js =~ "KEY_PROVIDE_WEATHER_FIELD1_TAG"
      assert generated_js =~ "KEY_PROVIDE_WEATHER_FIELD1_VALUE"
      assert generated_js =~ "KEY_PROVIDE_WIND_FIELD2_TAG"
      assert generated_js =~ "case \"ProvideWeather\":"
      assert generated_js =~ "case \"ProvideWind\":"

      assert generated_c =~ "elmc_release(phone_to_watch);"
      refute generated_c =~
               "companion_protocol_new_phone_to_watch_message(6, payload);\n            elmc_release(payload);"
    after
      File.rm_rf(tmp)
    end
  end

  test "inbox decoder omits watch-to-phone-only list and string slots" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-p2w-slots-#{System.unique_integer([:positive])}"
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
          = SendLabels (List String)

      type PhoneToWatch
          = SetWatchSeconds Int
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)

      generated_header = File.read!(header)
      generated_source = File.read!(source)

      refute generated_header =~ "COMPANION_PROTOCOL_LIST_MAX_ELEMENTS"
      refute generated_header =~ "list_values["
      refute generated_header =~ "string_fields["
      refute generated_header =~ "saw_wire_send_labels"
      refute generated_source =~ "saw_list_counts"

      assert generated_header =~ "COMPANION_PROTOCOL_KEY_SET_WATCH_SECONDS_FIELD1"
      assert generated_header =~ "COMPANION_PROTOCOL_TAG_SEND_LABELS"
    after
      File.rm_rf(tmp)
    end
  end

  test "IDE companion harness stub borrows payload (parity with elmc dispatch)" do
    # Must match elmc_pebble_dispatch_tag_payload borrow semantics; taking/releasing
    # here would hide double-frees that emery catches after companion ingest.
    source =
      File.read!(
        Path.expand("../../test/support/companion_protocol_c_harness.ex", __DIR__)
      )

    assert source =~ "Borrow semantics: caller retains ownership of payload"
    # Stub body must not free the caller's payload (generator releases after dispatch).
    refute source =~
             ~r/int elmc_pebble_dispatch_tag_payload\([\s\S]*?elmc_release\(\s*payload\s*\)/
  end
end
