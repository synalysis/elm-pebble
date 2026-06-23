defmodule Ide.CompanionProtocolCTestHarness do
  @moduledoc false

  alias Ide.CompanionProtocolGenerator
  alias Ide.CompanionProtocol.WireFlatten

  @wire_code_base CompanionProtocolGenerator.wire_code_base()

  @spec run_roundtrip!(String.t(), keyword()) :: :ok
  def run_roundtrip!(types_elm, opts \\ []) when is_binary(types_elm) do
    cc = System.find_executable("cc")

    if is_nil(cc) do
      raise "cc not available for companion protocol C round-trip test"
    end

    {:ok, schema} = CompanionProtocolGenerator.schema_from_source(File.read!(types_elm))
    out_dir = Keyword.get(opts, :out_dir) || temp_out_dir()

    generate_sources!(types_elm, schema, out_dir)
    harness_path = Path.join(out_dir, "harness.c")
    File.write!(harness_path, harness_c(schema))

    binary = Path.join(out_dir, "companion_protocol_roundtrip")

    {compile_out, compile_code} =
      System.cmd(cc, compile_args(out_dir, harness_path, binary), stderr_to_stdout: true)

    if compile_code != 0 do
      raise "companion protocol C harness compile failed:\n#{compile_out}"
    end

    {run_out, run_code} = System.cmd(binary, [], stderr_to_stdout: true)

    if run_code != 0 or not String.contains?(run_out, "companion_protocol_c_roundtrip: OK") do
      raise "companion protocol C harness run failed (exit #{run_code}):\n#{run_out}"
    end

    :ok
  end

  defp temp_out_dir do
    Path.join(
      System.tmp_dir!(),
      "companion-protocol-c-rt-#{System.unique_integer([:positive])}"
    )
  end

  defp generate_sources!(types_elm, _schema, out_dir) do
    generated_dir = Path.join(out_dir, "generated")
    elmc_dir = Path.join(out_dir, "elmc/c")
    File.mkdir_p!(generated_dir)
    File.mkdir_p!(elmc_dir)

    :ok =
      CompanionProtocolGenerator.generate(
        types_elm,
        Path.join(generated_dir, "companion_protocol.h"),
        Path.join(generated_dir, "companion_protocol.c"),
        Path.join(out_dir, "companion-protocol.js"),
        runtime_tags: runtime_tags_for_types(types_elm)
      )

    File.write!(Path.join(out_dir, "pebble.h"), pebble_h())
    File.write!(Path.join(elmc_dir, "elmc_pebble.h"), elmc_pebble_h())
    File.write!(Path.join(out_dir, "elmc_stubs.c"), elmc_stubs_c())
  end

  defp runtime_tags_for_types(types_elm) do
    cond do
      String.contains?(types_elm, "Temperature") ->
        %{
          "Temperature" => %{"Celsius" => 41, "Fahrenheit" => 42},
          "TutorialColor" => %{"Black" => 51, "White" => 52}
        }

      true ->
        %{}
    end
  end

  defp compile_args(out_dir, harness_path, binary) do
    generated = Path.join(out_dir, "generated")

    [
      "-std=c11",
      "-Wall",
      "-Wextra",
      "-Wno-unused-parameter",
      "-I#{out_dir}",
      "-I#{generated}",
      "-I#{Path.join(out_dir, "elmc/c")}",
      Path.join(generated, "companion_protocol.c"),
      Path.join(out_dir, "elmc_stubs.c"),
      harness_path,
      "-o",
      binary
    ]
  end

  defp harness_c(schema) do
    watch_tests = Enum.map_join(schema.watch_to_phone, "\n\n", &watch_encode_test/1)
    phone_tests = Enum.map_join(schema.phone_to_watch, "\n\n", &phone_decode_test(&1, schema))

    watch_count = length(schema.watch_to_phone)
    phone_count = length(schema.phone_to_watch)

    """
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include "companion_protocol.h"

    #define MAX_CAPTURED 48
    #define MAX_TUPLES 48

    typedef struct {
      uint32_t key;
      int32_t int_val;
      char str_val[64];
      bool is_string;
    } captured_entry_t;

    static captured_entry_t captured[MAX_CAPTURED];
    static int captured_count = 0;
    static int failures = 0;

    static TupleValue tuple_values[MAX_TUPLES];
    static Tuple tuples[MAX_TUPLES];
    static int tuple_count = 0;

    static void check_failed(const char *label) {
      fprintf(stderr, "CHECK failed: %s\\n", label);
      failures++;
    }

    #define CHECK(cond, label) \\
      do { \\
        if (!(cond)) { \\
          check_failed(label); \\
        } \\
      } while (0)

    static void dict_reset(void) {
      captured_count = 0;
    }

    static bool dict_has_int(uint32_t key, int32_t value) {
      for (int i = 0; i < captured_count; i++) {
        if (captured[i].key == key && !captured[i].is_string && captured[i].int_val == value) {
          return true;
        }
      }
      return false;
    }

    bool dict_write_int32(DictionaryIterator *iter, uint32_t key, int32_t value) {
      (void)iter;
      if (captured_count >= MAX_CAPTURED) {
        return false;
      }
      captured[captured_count].key = key;
      captured[captured_count].int_val = value;
      captured[captured_count].str_val[0] = '\\0';
      captured[captured_count].is_string = false;
      captured_count++;
      return true;
    }

    bool dict_write_cstring(DictionaryIterator *iter, uint32_t key, const char *value) {
      (void)iter;
      if (captured_count >= MAX_CAPTURED) {
        return false;
      }
      captured[captured_count].key = key;
      captured[captured_count].int_val = 0;
      strncpy(captured[captured_count].str_val, value ? value : "", sizeof(captured[captured_count].str_val) - 1);
      captured[captured_count].str_val[sizeof(captured[captured_count].str_val) - 1] = '\\0';
      captured[captured_count].is_string = true;
      return true;
    }

    static Tuple *make_int_tuple(uint32_t key, int32_t value) {
      if (tuple_count >= MAX_TUPLES) {
        return NULL;
      }
      TupleValue *tv = &tuple_values[tuple_count];
      Tuple *tuple = &tuples[tuple_count];
      tv->int32 = value;
      tuple->key = key;
      tuple->type = TUPLE_INT;
      tuple->length = (uint16_t)sizeof(int32_t);
      tuple->value = tv;
      tuple_count++;
      return tuple;
    }

    static Tuple *make_cstring_tuple(uint32_t key, const char *value) {
      if (tuple_count >= MAX_TUPLES) {
        return NULL;
      }
      TupleValue *tv = &tuple_values[tuple_count];
      Tuple *tuple = &tuples[tuple_count];
      strncpy(tv->cstring, value ? value : "", sizeof(tv->cstring) - 1);
      tv->cstring[sizeof(tv->cstring) - 1] = '\\0';
      tuple->key = key;
      tuple->type = TUPLE_CSTRING;
      tuple->length = (uint16_t)(strlen(tv->cstring) + 1);
      tuple->value = tv;
      tuple_count++;
      return tuple;
    }

    static void tuples_reset(void) {
      tuple_count = 0;
    }

    #{watch_tests}

    #{phone_tests}

    int main(void) {
      #{Enum.map_join(schema.watch_to_phone, "\n  ", fn msg -> "test_w2p_#{c_id(msg.name)}();" end)}
      #{Enum.map_join(schema.phone_to_watch, "\n  ", fn msg -> "test_p2w_#{c_id(msg.name)}();" end)}

      if (failures != 0) {
        fprintf(stderr, "companion_protocol_c_roundtrip: %d failure(s)\\n", failures);
        return 1;
      }

      printf("companion_protocol_c_roundtrip: OK (%d watch, %d phone)\\n", #{watch_count}, #{phone_count});
      return 0;
    }
    """
  end

  defp watch_encode_test(msg) do
    {_tag, value, expectations} = watch_encode_case(msg)
    tag_macro = "COMPANION_PROTOCOL_TAG_#{macro_name(msg.name)}"
    checks = Enum.map_join(expectations, "\n  ", &watch_expect_check/1)

    """
    static void test_w2p_#{c_id(msg.name)}(void) {
      DictionaryIterator iter;
      dict_reset();
      CHECK(companion_protocol_encode_watch_to_phone(&iter, #{tag_macro}, #{value}), "w2p #{msg.name} encode");
    #{checks}
    }
    """
  end

  defp watch_expect_check({key_name, int_value}) do
    key_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(key_name)}"
    "  CHECK(dict_has_int(#{key_macro}, #{int_value}), \"w2p key #{key_name}\");"
  end

  defp watch_encode_case(%{name: "Ping", tag: tag}) do
    {tag, 0, [{"message_tag", tag}]}
  end

  defp watch_encode_case(%{name: "RequestUpdate", tag: tag}) do
    {tag, 0, [{"message_tag", tag}]}
  end

  defp watch_encode_case(%{name: "RequestPhoneExtras", tag: tag}) do
    {tag, 0, [{"message_tag", tag}]}
  end

  defp watch_encode_case(%{name: "SendPoint", tag: tag}) do
    {tag, 0, [{"message_tag", tag}]}
  end

  defp watch_encode_case(%{name: "SendCounts", tag: tag}) do
    {tag, 0, [{"message_tag", tag}]}
  end

  defp watch_encode_case(%{name: "SendColor", tag: tag, fields: [field]}) do
    wire = wire_value_for_field(field, 0)
    {tag, wire, [{"message_tag", tag}, {field.key, wire}]}
  end

  defp watch_encode_case(%{name: "SendMeasure", tag: tag, fields: [field]}) do
    wire = wire_value_for_field(field, 0)
    {tag, wire, [{"message_tag", tag}, {field.key <> "_tag", wire}, {field.key <> "_value", 0}]}
  end

  defp watch_encode_case(%{name: "RequestWeather", tag: tag, fields: [field]}) do
    wire = wire_value_for_field(field, 1)
    {tag, wire, [{"message_tag", tag}, {field.key, wire}]}
  end

  defp watch_encode_case(msg) do
    raise "unsupported watch encode case #{inspect(msg.name)}"
  end

  defp phone_decode_test(msg, schema) do
    kind_macro = "COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_#{macro_name(msg.name)}"
    wire = phone_wire_tuples(msg, schema)
    tuple_setup = Enum.map_join(Enum.with_index(wire), "\n  ", &phone_tuple_setup/1)
    assertions = phone_decode_assertions(msg, schema)

    """
    static void test_p2w_#{c_id(msg.name)}(void) {
      tuples_reset();
    #{tuple_setup}
      const Tuple *wire_tuples[#{length(wire)}];
    #{Enum.map_join(0..(length(wire) - 1), "\n  ", fn i -> "  wire_tuples[#{i}] = &tuples[#{i}];" end)}

      CompanionProtocolPhoneToWatchDecoder decoder;
      CompanionProtocolPhoneToWatchMessage message;
      companion_protocol_phone_to_watch_decoder_init(&decoder);
      for (int i = 0; i < #{length(wire)}; i++) {
        companion_protocol_phone_to_watch_decoder_push_tuple(&decoder, wire_tuples[i]);
      }

      CHECK(companion_protocol_phone_to_watch_decoder_finish(&decoder, &message), "p2w #{msg.name} decode");
      CHECK(message.kind == #{kind_macro}, "p2w #{msg.name} kind");
    #{assertions}
    }
    """
  end

  defp phone_tuple_setup({{type, key_name, value}, _index}) do
    key_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(key_name)}"

    case type do
      :int ->
        "  make_int_tuple(#{key_macro}, #{value});"

      :cstring ->
        "  make_cstring_tuple(#{key_macro}, \"#{value}\");"
    end
  end

  defp phone_wire_tuples(%{name: "Pong", tag: tag}, _schema) do
    [{:int, "message_tag", tag}]
  end

  defp phone_wire_tuples(%{name: "SetShowDate", tag: tag, fields: [field]}, _schema) do
    [{:int, "message_tag", tag}, {:int, field.key, @wire_code_base}]
  end

  defp phone_wire_tuples(%{name: "SetLabel", tag: tag, fields: [field]}, _schema) do
    [{:int, "message_tag", tag}, {:cstring, field.key, "elm"}]
  end

  defp phone_wire_tuples(%{name: "PushString", tag: tag, fields: [field]}, _schema) do
    [{:int, "message_tag", tag}, {:cstring, field.key, "elm"}]
  end

  defp phone_wire_tuples(%{name: "PushBool", tag: tag, fields: [field]}, _schema) do
    [{:int, "message_tag", tag}, {:int, field.key, @wire_code_base}]
  end

  defp phone_wire_tuples(%{name: name, tag: tag, fields: [field]}, _schema)
       when name in ["EchoColor", "SetBackgroundColor"] do
    wire = wire_value_for_field(field, 0)
    [{:int, "message_tag", tag}, {:int, field.key, wire}]
  end

  defp phone_wire_tuples(%{name: "EchoMeasure", tag: tag, fields: [field]}, _schema) do
    [{:int, "message_tag", tag}, {:int, field.key <> "_tag", @wire_code_base}, {:int, field.key <> "_value", 5}]
  end

  defp phone_wire_tuples(%{name: "ProvideTemperature", tag: tag, fields: [field]}, _schema) do
    [{:int, "message_tag", tag}, {:int, field.key <> "_tag", @wire_code_base}, {:int, field.key <> "_value", 72}]
  end

  defp phone_wire_tuples(%{name: "EchoPoint", tag: tag, fields: [field]}, schema) do
    wire_tuples_for_record(tag, field, schema, 1, 2)
  end

  defp phone_wire_tuples(%{name: "EchoCounts", tag: tag, fields: [field]}, schema) do
    wire_tuples_for_list(tag, field, schema, [1, 2, 3])
  end

  defp phone_wire_tuples(%{name: "PushPoints", tag: tag, fields: [field]}, schema) do
    wire_tuples_for_point_list(tag, field, schema, [%{x: 4, y: 5}])
  end

  defp phone_wire_tuples(%{name: "PushLabels", tag: tag, fields: [field]}, schema) do
    wire_tuples_for_dict(tag, field, schema, %{"k" => 9})
  end

  defp phone_wire_tuples(msg, _schema) do
    raise "unsupported phone decode case #{inspect(msg.name)}"
  end

  defp wire_tuples_for_record(tag, field, schema, x, y) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))

    base = [{:int, "message_tag", tag}]

    Enum.reduce(slots, base, fn slot, acc ->
      value =
        cond do
          String.ends_with?(slot.key, "_x") -> x
          String.ends_with?(slot.key, "_y") -> y
          true -> 0
        end

      [{:int, slot.key, value} | acc]
    end)
    |> Enum.reverse()
  end

  defp wire_tuples_for_list(tag, field, schema, values) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))
    count_slot = list_count_slot(slots)

    base = [
      {:int, "message_tag", tag},
      {:int, count_slot.key, length(values) + @wire_code_base}
    ]

    elements =
      Enum.flat_map(Enum.with_index(values), fn {value, index} ->
        list_index_slots(slots, index)
        |> Enum.map(fn slot ->
          offset = if slot.wire_offset == :offset, do: @wire_code_base, else: 0
          {:int, slot.key, value + offset}
        end)
      end)

    base ++ elements
  end

  defp wire_tuples_for_point_list(tag, field, schema, points) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))
    count_slot = list_count_slot(slots)

    base = [
      {:int, "message_tag", tag},
      {:int, count_slot.key, length(points) + @wire_code_base}
    ]

    elements =
      Enum.flat_map(Enum.with_index(points), fn {point, index} ->
        list_index_slots(slots, index)
        |> Enum.map(fn slot ->
          value =
            cond do
              String.ends_with?(slot.key, "_x") -> point.x
              String.ends_with?(slot.key, "_y") -> point.y
              true -> 0
            end

          {:int, slot.key, value}
        end)
      end)

    base ++ elements
  end

  defp wire_tuples_for_dict(tag, field, schema, entries) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))
    count_slot = dict_count_slot(slots)
    pairs = Map.to_list(entries)

    base = [
      {:int, "message_tag", tag},
      {:int, count_slot.key, length(pairs) + @wire_code_base}
    ]

    pair_slots =
      Enum.flat_map(0..(length(pairs) - 1), fn index ->
        key_slot = dict_key_slot(slots, index)
        val_slot = dict_value_slot(slots, index)
        {key, val} = Enum.at(pairs, index)

        offset = if val_slot.wire_offset == :offset, do: @wire_code_base, else: 0
        [{:cstring, key_slot.key, key}, {:int, val_slot.key, val + offset}]
      end)

    base ++ pair_slots
  end

  defp list_count_slot(slots) do
    Enum.find(slots, fn slot ->
      match?(%{kind: :list_count}, List.last(slot.path))
    end)
  end

  defp list_index_slots(slots, index) do
    Enum.filter(slots, fn slot ->
      case List.last(slot.path) do
        %{kind: :list_index, index: ^index} -> true
        _ -> false
      end
    end)
  end

  defp dict_count_slot(slots) do
    Enum.find(slots, fn slot ->
      match?(%{kind: :dict_count}, List.last(slot.path))
    end)
  end

  defp dict_key_slot(slots, index) do
    Enum.find(slots, fn slot ->
      case List.last(slot.path) do
        %{kind: :dict_key, index: ^index} -> true
        _ -> false
      end
    end)
  end

  defp dict_value_slot(slots, index) do
    Enum.find(slots, fn slot ->
      case List.last(slot.path) do
        %{kind: :dict_value, index: ^index} -> true
        _ -> false
      end
    end)
  end

  defp phone_decode_assertions(%{name: "EchoColor", fields: [_field]}, _schema) do
    "  CHECK(message.int_fields[0] == #{@wire_code_base}, \"p2w EchoColor field\");"
  end

  defp phone_decode_assertions(%{name: "EchoMeasure"}, _schema) do
    """
      CHECK(message.int_fields[0] == #{@wire_code_base}, "p2w EchoMeasure tag");
      CHECK(message.union_value_fields[0] == 5, "p2w EchoMeasure value");
    """
  end

  defp phone_decode_assertions(%{name: "ProvideTemperature"}, _schema) do
    """
      CHECK(message.int_fields[0] == #{@wire_code_base}, "p2w ProvideTemperature tag");
      CHECK(message.union_value_fields[0] == 72, "p2w ProvideTemperature value");
    """
  end

  defp phone_decode_assertions(%{name: "EchoPoint", fields: [field]}, schema) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))

    Enum.map_join(slots, "\n", fn slot ->
      expected =
        cond do
          String.ends_with?(slot.c_name, "_x") -> 1
          String.ends_with?(slot.c_name, "_y") -> 2
          true -> 0
        end

      "  CHECK(message.wire.#{slot.c_name} == #{expected}, \"p2w EchoPoint #{slot.c_name}\");"
    end)
  end

  defp phone_decode_assertions(%{name: "EchoCounts", fields: [_field]}, _schema) do
    """
      CHECK(message.list_counts[0] == 3, "p2w EchoCounts count");
      CHECK(message.list_values[0][0] == 1, "p2w EchoCounts elem 0");
      CHECK(message.list_values[0][1] == 2, "p2w EchoCounts elem 1");
      CHECK(message.list_values[0][2] == 3, "p2w EchoCounts elem 2");
    """
  end

  defp phone_decode_assertions(%{name: "PushBool"}, _schema) do
    "  CHECK(message.bool_fields[0] == true, \"p2w PushBool field\");"
  end

  defp phone_decode_assertions(%{name: "SetShowDate"}, _schema) do
    "  CHECK(message.bool_fields[0] == true, \"p2w SetShowDate field\");"
  end

  defp phone_decode_assertions(%{name: name}, _schema) when name in ["PushString", "SetLabel"] do
    "  CHECK(strcmp(message.string_fields[0], \"elm\") == 0, \"p2w #{name} field\");"
  end

  defp phone_decode_assertions(%{name: "PushPoints", fields: [field]}, schema) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))
    count_slot = list_count_slot(slots)

    count_check =
      "  CHECK(message.wire.#{count_slot.c_name} == 1, \"p2w PushPoints count\");"

    element_checks =
      list_index_slots(slots, 0)
      |> Enum.map_join("\n", fn slot ->
        expected =
          cond do
            String.ends_with?(slot.key, "_x") -> 4
            String.ends_with?(slot.key, "_y") -> 5
            true -> 0
          end

        "  CHECK(message.wire.#{slot.c_name} == #{expected}, \"p2w PushPoints #{slot.c_name}\");"
      end)

    count_check <> "\n" <> element_checks
  end

  defp phone_decode_assertions(%{name: "PushLabels", fields: [field]}, schema) do
    slots = WireFlatten.slots_for_field(field, schema_context(schema))
    count_slot = dict_count_slot(slots)
    key_slot = dict_key_slot(slots, 0)
    val_slot = dict_value_slot(slots, 0)

    """
      CHECK(message.wire.#{count_slot.c_name} == 1, "p2w PushLabels count");
      CHECK(strcmp(message.wire.#{key_slot.c_name}, "k") == 0, "p2w PushLabels key");
      CHECK(message.wire.#{val_slot.c_name} == 9, "p2w PushLabels value");
    """
  end

  defp phone_decode_assertions(%{name: "SetBackgroundColor"}, _schema) do
    "  CHECK(message.int_fields[0] == #{@wire_code_base}, \"p2w SetBackgroundColor field\");"
  end

  defp phone_decode_assertions(%{name: name}, _schema) when name in ["Pong"] do
    ""
  end

  defp phone_decode_assertions(msg, _schema) do
    raise "missing phone decode assertions for #{inspect(msg.name)}"
  end

  defp wire_value_for_field(%{wire_type: {:enum, type}}, index) do
    ctors = enum_constructors(type)
    wire_code(index, ctors)
  end

  defp wire_value_for_field(%{wire_type: {:union, type}}, index) do
  ctors = union_constructors(type)
    wire_code(index, ctors)
  end

  defp wire_value_for_field(_field, _index), do: 0

  defp wire_code(index, ctors) when is_list(ctors) do
    if index < length(ctors), do: index + @wire_code_base, else: @wire_code_base
  end

  defp enum_constructors("Color"), do: ["Red", "Green", "Blue"]
  defp enum_constructors("TutorialColor"), do: ["Black", "White"]
  defp enum_constructors("Location"), do: ["CurrentLocation", "Berlin", "Zurich"]
  defp enum_constructors(_), do: []

  defp union_constructors("Measure"), do: ["Liters", "Pounds"]
  defp union_constructors("Temperature"), do: ["Celsius", "Fahrenheit"]
  defp union_constructors(_), do: []

  defp schema_context(schema) do
    %{
      enums: schema.enums,
      payload_unions: schema.payload_unions,
      type_aliases: schema.type_aliases
    }
  end

  defp macro_name(value) do
    value
    |> to_string()
    |> camel_to_snake()
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.upcase()
  end

  defp camel_to_snake(value) do
    value
    |> to_string()
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  defp c_id(name) do
    name
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.trim("_")
    |> String.downcase()
  end

  defp pebble_h do
    """
    #ifndef PEBBLE_H_STUB
    #define PEBBLE_H_STUB

    #include <stdint.h>
    #include <stdbool.h>
    #include <string.h>

    typedef enum {
      TUPLE_INT = 0,
      TUPLE_UINT = 2,
      TUPLE_CSTRING = 3,
    } TupleType;

    typedef union {
      int32_t int32;
      uint32_t uint32;
      char cstring[64];
    } TupleValue;

    typedef struct {
      uint32_t key;
      TupleType type;
      uint16_t length;
      TupleValue *value;
    } Tuple;

    typedef struct DictionaryIterator {
      int unused;
    } DictionaryIterator;

    bool dict_write_int32(DictionaryIterator *iter, uint32_t key, int32_t value);
    bool dict_write_cstring(DictionaryIterator *iter, uint32_t key, const char *value);

    #endif
    """
  end

  defp elmc_pebble_h do
    """
    #ifndef ELMC_PEBBLE_H_STUB
    #define ELMC_PEBBLE_H_STUB

    #include <stdint.h>
    #include <stdbool.h>

    typedef struct ElmcValue ElmcValue;
    typedef struct ElmcPebbleApp ElmcPebbleApp;

    #define ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET 3

    ElmcValue *elmc_new_int_take(int64_t value);
    ElmcValue *elmc_new_bool_take(bool value);
    ElmcValue *elmc_new_string_take(const char *value);
    ElmcValue *elmc_tuple2_take_value(ElmcValue *left, ElmcValue *right);
    ElmcValue *elmc_record_new_take_value(int field_count, const char **names, ElmcValue **values);
    ElmcValue *elmc_list_from_int_array_take(const int32_t *values, int count);
    ElmcValue *elmc_list_from_values_take_value(ElmcValue **values, int count);
    ElmcValue *elmc_dict_from_list_take(ElmcValue *pairs);
    void elmc_release(ElmcValue *value);
    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload);
    int elmc_pebble_dispatch_tag_int_values(
        ElmcPebbleApp *app,
        int64_t tag,
        int64_t ctor_tag,
        int value_count,
        const int64_t *values);

    #endif
    """
  end

  defp elmc_stubs_c do
    """
    #include "elmc_pebble.h"
    #include <stdbool.h>
    #include <stdlib.h>

    struct ElmcValue {
      int tag;
      void *payload;
    };

    struct ElmcPebbleApp {
      int initialized;
    };

    ElmcValue *elmc_new_int_take(int64_t value) {
      ElmcValue *v = calloc(1, sizeof(ElmcValue));
      if (v) {
        v->tag = 1;
        v->payload = (void *)(intptr_t)value;
      }
      return v;
    }

    ElmcValue *elmc_new_bool_take(bool value) {
      return elmc_new_int_take(value ? 1 : 0);
    }

    ElmcValue *elmc_new_string_take(const char *value) {
      (void)value;
      return calloc(1, sizeof(ElmcValue));
    }

    ElmcValue *elmc_tuple2_take_value(ElmcValue *left, ElmcValue *right) {
      (void)left;
      (void)right;
      return calloc(1, sizeof(ElmcValue));
    }

    ElmcValue *elmc_record_new_take_value(int field_count, const char **names, ElmcValue **values) {
      (void)field_count;
      (void)names;
      (void)values;
      return calloc(1, sizeof(ElmcValue));
    }

    ElmcValue *elmc_list_from_int_array_take(const int32_t *values, int count) {
      (void)values;
      (void)count;
      return calloc(1, sizeof(ElmcValue));
    }

    ElmcValue *elmc_list_from_values_take_value(ElmcValue **values, int count) {
      (void)values;
      (void)count;
      return calloc(1, sizeof(ElmcValue));
    }

    ElmcValue *elmc_dict_from_list_take(ElmcValue *pairs) {
      (void)pairs;
      return calloc(1, sizeof(ElmcValue));
    }

    void elmc_release(ElmcValue *value) {
      free(value);
    }

    int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload) {
      (void)app;
      (void)tag;
      elmc_release(payload);
      return 0;
    }

    int elmc_pebble_dispatch_tag_int_values(
        ElmcPebbleApp *app,
        int64_t tag,
        int64_t ctor_tag,
        int value_count,
        const int64_t *values) {
      (void)app;
      (void)tag;
      (void)ctor_tag;
      (void)value_count;
      (void)values;
      return 0;
    }
    """
  end
end
