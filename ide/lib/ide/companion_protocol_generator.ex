defmodule Ide.CompanionProtocolGenerator do
  @moduledoc false

  alias Ide.Debugger.Protocol.Schema

  @type schema :: Schema.t()
  @type constructor :: Schema.constructor()
  @type message :: Schema.message()
  @type field :: Schema.field()

  @type generator_error :: {:missing_union, String.t()} | File.posix()

  # Pebble AppMessage commonly drops dictionary entries whose value is zero.
  # Enum and union-tag wire codes therefore start at 1; bool uses 1=true, 2=false.
  @wire_code_base 1
  @wire_true_code 1
  @wire_false_code 2
  @list_max_elements 16

  @spec wire_code_base() :: pos_integer()
  def wire_code_base, do: @wire_code_base

  defp wire_code(index) when is_integer(index), do: index + @wire_code_base

  @spec generate(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, generator_error()}
  def generate(types_elm, out_h, out_c, out_js, opts \\ []) do
    with {:ok, source} <- File.read(types_elm),
         {:ok, schema} <- schema_from_source(source),
         :ok <- File.mkdir_p(Path.dirname(out_h)),
         :ok <- File.mkdir_p(Path.dirname(out_js)),
         :ok <- File.write(out_h, header(schema)),
         :ok <- File.write(out_c, source(schema, opts)),
         :ok <- File.write(out_js, js(schema)) do
      :ok
    end
  end

  @spec generate_elm_internal(String.t(), String.t()) :: :ok | {:error, generator_error()}
  def generate_elm_internal(types_elm, out_elm) do
    with {:ok, source} <- File.read(types_elm),
         {:ok, schema} <- schema_from_source(source),
         :ok <- File.mkdir_p(Path.dirname(out_elm)),
         :ok <- File.write(out_elm, elm_internal(schema)) do
      :ok
    end
  end

  @spec message_keys(String.t()) ::
          {:ok, %{optional(String.t()) => pos_integer()}} | {:error, generator_error()}
  def message_keys(types_elm) do
    with {:ok, source} <- File.read(types_elm),
         {:ok, schema} <- schema_from_source(source) do
      {:ok, schema.key_ids}
    end
  end

  @spec schema_from_source(String.t()) :: {:ok, schema()} | {:error, generator_error()}
  def schema_from_source(source) when is_binary(source) do
    unions = parse_unions(source)
    enums = enum_unions(unions, ["WatchToPhone", "PhoneToWatch"])
    payload_unions = payload_unions(unions, enums, ["WatchToPhone", "PhoneToWatch"])

    with {:ok, watch_to_phone} <- message_union(unions, enums, payload_unions, "WatchToPhone", 2),
         {:ok, phone_to_watch} <-
           message_union(unions, enums, payload_unions, "PhoneToWatch", 201) do
      messages = watch_to_phone ++ phone_to_watch

      key_names =
        ["message_tag"] ++
          (messages
           |> Enum.flat_map(& &1.fields)
           |> Enum.flat_map(&field_keys/1)
           |> Enum.uniq())

      key_ids =
        key_names
        |> Enum.with_index(10)
        |> Map.new(fn {name, id} -> {name, id} end)

      {:ok,
       %{
         enums: enums,
         payload_unions: payload_unions,
         watch_to_phone: watch_to_phone,
         phone_to_watch: phone_to_watch,
         key_ids: key_ids
       }}
    end
  end

  defp parse_unions(source) do
    ~r/(?:^|\n)type\s+([A-Z][A-Za-z0-9_]*)\s*\n((?:\s{4}=\s+[A-Z][^\n]*(?:\n\s{4}\|\s+[A-Z][^\n]*)*|\s+=\s+[A-Z][^\n]*(?:\n\s+\|\s+[A-Z][^\n]*)*))/m
    |> Regex.scan(source)
    |> Map.new(fn [_all, name, body] ->
      constructors =
        body
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.trim_leading(&1, "="))
        |> Enum.map(&String.trim_leading(&1, "|"))
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&parse_constructor_line/1)

      {name, constructors}
    end)
  end

  defp enum_unions(unions, excluded) do
    unions
    |> Enum.reject(fn {name, _} -> name in excluded end)
    |> Enum.filter(fn {_name, ctors} -> Enum.all?(ctors, &(Map.get(&1, :args, []) == [])) end)
    |> Map.new(fn {name, ctors} -> {name, Enum.map(ctors, & &1.name)} end)
  end

  defp payload_unions(unions, enums, excluded) do
    unions
    |> Enum.reject(fn {name, _} -> name in excluded or Map.has_key?(enums, name) end)
    |> Map.new()
  end

  defp message_union(unions, enums, payload_unions, name, first_tag) do
    case Map.fetch(unions, name) do
      {:ok, constructors} ->
        messages =
          constructors
          |> Enum.with_index(first_tag)
          |> Enum.map(fn {ctor, tag} ->
            fields =
              ctor.args
              |> Enum.with_index(1)
              |> Enum.map(fn {type, index} ->
                %{
                  name: "field#{index}",
                  key: "#{camel_to_snake(ctor.name)}_field#{index}",
                  type: type,
                  wire_type: wire_type(type, enums, payload_unions)
                }
              end)

            %{name: ctor.name, tag: tag, fields: fields}
          end)

        {:ok, messages}

      :error ->
        {:error, {:missing_union, name}}
    end
  end

  defp parse_constructor_line(line) do
    [ctor | raw_args] = String.split(line, ~r/\s+/, trim: true)
    %{name: ctor, args: normalize_constructor_args(raw_args)}
  end

  defp normalize_constructor_args(raw_args) do
    raw_args
    |> Enum.join(" ")
    |> String.replace(~r/[()]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> collapse_list_type_tokens([])
  end

  defp collapse_list_type_tokens([], acc), do: Enum.reverse(acc)

  defp collapse_list_type_tokens(["List", type | rest], acc),
    do: collapse_list_type_tokens(rest, ["List #{type}" | acc])

  defp collapse_list_type_tokens([head | rest], acc),
    do: collapse_list_type_tokens(rest, [head | acc])

  defp wire_type("Int", _enums, _payload_unions), do: :int
  defp wire_type("Bool", _enums, _payload_unions), do: :bool
  defp wire_type("String", _enums, _payload_unions), do: :string
  defp wire_type("List Int", _enums, _payload_unions), do: {:list, :int}

  defp wire_type(type, enums, payload_unions) do
    cond do
      Map.has_key?(enums, type) -> {:enum, type}
      Map.has_key?(payload_unions, type) -> {:union, type}
      true -> :int
    end
  end

  defp field_keys(%{wire_type: {:union, _type}, key: key}), do: [key <> "_tag", key <> "_value"]

  defp field_keys(%{wire_type: {:list, :int}, key: key}) do
    [key <> "_count" | Enum.map(0..(@list_max_elements - 1), &"#{key}_#{&1}")]
  end

  defp field_keys(%{key: key}), do: [key]

  defp header(schema) do
    key_lines =
      schema.key_ids
      |> Enum.sort_by(fn {_name, id} -> id end)
      |> Enum.map_join("\n", fn {name, id} ->
        "#define COMPANION_PROTOCOL_KEY_#{macro_name(name)} #{id}"
      end)

    enum_lines =
      schema.enums
      |> Enum.flat_map(fn {type, ctors} ->
        ctors
        |> Enum.with_index()
        |> Enum.map(fn {ctor, index} ->
          "#define COMPANION_PROTOCOL_ENUM_#{macro_name(type)}_#{macro_name(ctor)} #{wire_code(index)}"
        end)
      end)
      |> Enum.join("\n")

    tag_lines =
      (schema.watch_to_phone ++ schema.phone_to_watch)
      |> Enum.map_join("\n", fn msg ->
        "#define COMPANION_PROTOCOL_TAG_#{macro_name(msg.name)} #{msg.tag}"
      end)

    kind_lines =
      schema.phone_to_watch
      |> Enum.map_join("\n", fn msg ->
        "  COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_#{macro_name(msg.name)},"
      end)

    max_fields =
      schema.phone_to_watch
      |> Enum.map(&length(&1.fields))
      |> Enum.max(fn -> 0 end)
      |> max(1)

    uses_union_payloads? = companion_protocol_uses_union_payloads?(schema)
    uses_bool_payloads? = companion_protocol_uses_payload_type?(schema, :bool)
    uses_string_payloads? = companion_protocol_uses_payload_type?(schema, :string)
    uses_list_payloads? = companion_protocol_uses_list_payloads?(schema)

    message_fields =
      [
        "  CompanionProtocolPhoneToWatchKind kind;",
        "  int32_t int_fields[COMPANION_PROTOCOL_MAX_FIELDS];"
      ] ++
        optional_c_struct_field(
          uses_list_payloads?,
          "  int32_t list_counts[COMPANION_PROTOCOL_MAX_FIELDS];"
        ) ++
        optional_c_struct_field(
          uses_list_payloads?,
          "  int32_t list_values[COMPANION_PROTOCOL_MAX_FIELDS][COMPANION_PROTOCOL_LIST_MAX_ELEMENTS];"
        ) ++
        optional_c_struct_field(
          uses_union_payloads?,
          "  int32_t union_value_fields[COMPANION_PROTOCOL_MAX_FIELDS];"
        ) ++
        optional_c_struct_field(
          uses_bool_payloads?,
          "  bool bool_fields[COMPANION_PROTOCOL_MAX_FIELDS];"
        ) ++
        optional_c_struct_field(
          uses_string_payloads?,
          "  char string_fields[COMPANION_PROTOCOL_MAX_FIELDS][64];"
        )

    decoder_fields =
      [
        "  bool saw_tag;",
        "  int32_t tag;",
        "  CompanionProtocolPhoneToWatchMessage message;",
        "  bool saw_fields[COMPANION_PROTOCOL_MAX_FIELDS];"
      ] ++
        optional_c_struct_field(
          uses_union_payloads?,
          "  bool saw_union_value_fields[COMPANION_PROTOCOL_MAX_FIELDS];"
        ) ++
        optional_c_struct_field(
          uses_list_payloads?,
          "  bool saw_list_counts[COMPANION_PROTOCOL_MAX_FIELDS];"
        ) ++
        optional_c_struct_field(
          uses_list_payloads?,
          "  bool saw_list_elements[COMPANION_PROTOCOL_MAX_FIELDS][COMPANION_PROTOCOL_LIST_MAX_ELEMENTS];"
        )

    list_macros =
      if uses_list_payloads? do
        """
        #define COMPANION_PROTOCOL_LIST_MAX_ELEMENTS #{@list_max_elements}
        #define COMPANION_PROTOCOL_LIST_WIRE_OFFSET #{@wire_code_base}
        """
      else
        ""
      end

    """
    #ifndef COMPANION_PROTOCOL_H
    #define COMPANION_PROTOCOL_H

    #include <pebble.h>
    #include <stdbool.h>
    #include <stdint.h>
    #include "../elmc/c/elmc_pebble.h"

    #{key_lines}
    #{enum_lines}
    #{tag_lines}

    #define COMPANION_PROTOCOL_MAX_FIELDS #{max_fields}
    #{list_macros}#{companion_simulator_weather_macros(schema, uses_union_payloads?)}

    typedef enum {
      COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN = 0,
    #{kind_lines}
    } CompanionProtocolPhoneToWatchKind;

    typedef struct {
    #{Enum.join(message_fields, "\n")}
    } CompanionProtocolPhoneToWatchMessage;

    typedef struct {
    #{Enum.join(decoder_fields, "\n")}
    } CompanionProtocolPhoneToWatchDecoder;

    bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value);
    void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder);
    void companion_protocol_phone_to_watch_decoder_push_tuple(
        CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple);
    bool companion_protocol_phone_to_watch_decoder_finish(
        CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out);
    int companion_protocol_dispatch_phone_to_watch(
        ElmcPebbleApp *app, const CompanionProtocolPhoneToWatchMessage *message);

    #endif
    """
  end

  defp source(schema, opts) do
    runtime_tags = Keyword.get(opts, :runtime_tags, %{})

    w2p_cases =
      schema.watch_to_phone
      |> Enum.map_join("\n", fn msg ->
        field = List.first(msg.fields)
        writes = c_write_tuple(field, schema.key_ids)

        """
            case COMPANION_PROTOCOL_TAG_#{macro_name(msg.name)}:
              dict_write_int32(iter, COMPANION_PROTOCOL_KEY_MESSAGE_TAG, COMPANION_PROTOCOL_TAG_#{macro_name(msg.name)});
        #{writes}
              return true;
        """
      end)

    push_cases =
      schema.phone_to_watch
      |> Enum.flat_map(fn msg ->
        msg.fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} -> c_decode_tuple_cases(field, index) end)
      end)
      |> Enum.join("\n")

    finish_cases =
      schema.phone_to_watch
      |> Enum.map_join("\n", fn msg ->
        missing_field_defaults = c_missing_field_defaults(msg)

        required =
          msg.fields
          |> Enum.with_index()
          |> Enum.map_join(" && ", fn {field, index} -> c_required_field_expr(field, index) end)

        required = if required == "", do: "true", else: required

        """
            case COMPANION_PROTOCOL_TAG_#{macro_name(msg.name)}:
        #{missing_field_defaults}      if (!(#{required})) return false;
              *out = decoder->message;
              out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_#{macro_name(msg.name)};
              return true;
        """
      end)

    dispatch_cases =
      schema.phone_to_watch
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {msg, phone_to_watch_tag} ->
        c_dispatch_case(msg, phone_to_watch_tag)
      end)

    union_value_helper =
      if companion_protocol_uses_union_payloads?(schema) do
        """
        static ElmcValue *companion_protocol_new_union_value(int32_t runtime_tag, int32_t value) {
          ElmcValue *tag_value = elmc_new_int(runtime_tag);
          ElmcValue *payload_value = elmc_new_int(value);
          if (!tag_value || !payload_value) {
            if (tag_value) elmc_release(tag_value);
            if (payload_value) elmc_release(payload_value);
            return NULL;
          }

          ElmcValue *out = elmc_tuple2(tag_value, payload_value);
          elmc_release(tag_value);
          elmc_release(payload_value);
          return out;
        }
        """
      else
        ""
      end

    phone_to_watch_helper =
      if companion_protocol_uses_boxed_dispatch?(schema) do
        """
        static ElmcValue *companion_protocol_new_phone_to_watch_message(int32_t tag, ElmcValue *payload) {
          if (!payload) return NULL;
          ElmcValue *tag_value = elmc_new_int(tag);
          if (!tag_value) return NULL;

          ElmcValue *out = elmc_tuple2(tag_value, payload);
          elmc_release(tag_value);
          return out;
        }
        """
      else
        ""
      end

    """
    #include "companion_protocol.h"
    #include <string.h>

    #{c_runtime_tag_helpers(schema, runtime_tags)}

    #{union_value_helper}

    #{phone_to_watch_helper}

    #{c_list_wire_helpers(schema)}

    bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value) {
      if (!iter) return false;
      switch (tag) {
    #{w2p_cases}
        default:
          return false;
      }
    }

    void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder) {
      if (!decoder) return;
      decoder->saw_tag = false;
      decoder->tag = 0;
      memset(&decoder->message, 0, sizeof(decoder->message));
      memset(decoder->saw_fields, 0, sizeof(decoder->saw_fields));
    #{c_init_union_seen_fields(schema)}
    #{c_init_list_seen_fields(schema)}
    }

    void companion_protocol_phone_to_watch_decoder_push_tuple(
        CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple) {
      if (!decoder || !tuple) return;

      if (tuple->key == COMPANION_PROTOCOL_KEY_MESSAGE_TAG &&
          (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT)) {
        decoder->tag = tuple->value->int32;
        decoder->saw_tag = true;
        return;
      }

    #{push_cases}
    }

    bool companion_protocol_phone_to_watch_decoder_finish(
        CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out) {
      if (!decoder || !out || !decoder->saw_tag) return false;

      switch (decoder->tag) {
    #{finish_cases}
        default:
          out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN;
          return false;
      }
    }

    int companion_protocol_dispatch_phone_to_watch(
        ElmcPebbleApp *app, const CompanionProtocolPhoneToWatchMessage *message) {
      if (!app || !message) return -1;

      switch (message->kind) {
    #{dispatch_cases}
        default:
          return -6;
      }
    }
    """
  end

  defp companion_protocol_uses_union_payloads?(schema) do
    schema_fields(schema)
    |> Enum.any?(fn
      %{wire_type: {:union, _type}} -> true
      _field -> false
    end)
  end

  defp companion_protocol_uses_list_payloads?(schema) do
    schema_fields(schema)
    |> Enum.any?(fn
      %{wire_type: {:list, _elem}} -> true
      _field -> false
    end)
  end

  defp companion_protocol_uses_payload_type?(schema, wire_type) do
    schema_fields(schema)
    |> Enum.any?(&(&1.wire_type == wire_type))
  end

  defp schema_fields(schema) do
    (schema.watch_to_phone ++ schema.phone_to_watch)
    |> Enum.flat_map(& &1.fields)
  end

  defp optional_c_struct_field(true, field), do: [field]
  defp optional_c_struct_field(false, _field), do: []

  defp companion_simulator_weather_macros(schema, uses_union_payloads?) do
    names = schema.phone_to_watch |> Enum.map(& &1.name) |> MapSet.new()

    mode =
      cond do
        MapSet.member?(names, "ProvideWeather") ->
          "#define ELMC_COMPANION_SIMULATOR_WEATHER_MODE_UNIFIED 1"

        MapSet.member?(names, "ProvideTemperature") and MapSet.member?(names, "ProvideCondition") ->
          "#define ELMC_COMPANION_SIMULATOR_WEATHER_MODE_LEGACY_SPLIT 1"

        MapSet.member?(names, "ProvideTemperature") ->
          "#define ELMC_COMPANION_SIMULATOR_WEATHER_MODE_TEMPERATURE_ONLY 1"

        true ->
          nil
      end

    weather_enabled? = not is_nil(mode)

    lines =
      [
        "#define ELMC_COMPANION_SIMULATOR_WEATHER #{if weather_enabled?, do: 1, else: 0}",
        "#define ELMC_COMPANION_PROTOCOL_HAS_UNION_PAYLOADS #{if uses_union_payloads?, do: 1, else: 0}",
        mode
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\n")
  end

  defp c_init_union_seen_fields(schema) do
    if companion_protocol_uses_union_payloads?(schema) do
      "  memset(decoder->saw_union_value_fields, 0, sizeof(decoder->saw_union_value_fields));"
    else
      ""
    end
  end

  defp c_init_list_seen_fields(schema) do
    if companion_protocol_uses_list_payloads?(schema) do
      """
        memset(decoder->saw_list_counts, 0, sizeof(decoder->saw_list_counts));
        memset(decoder->saw_list_elements, 0, sizeof(decoder->saw_list_elements));
      """
    else
      ""
    end
  end

  defp c_list_wire_helpers(schema) do
    if companion_protocol_uses_list_payloads?(schema) do
      """
      static int32_t companion_protocol_decode_list_wire_int(int32_t wire) {
        return wire - COMPANION_PROTOCOL_LIST_WIRE_OFFSET;
      }

      static int32_t companion_protocol_decode_list_wire_count(int32_t wire) {
        int32_t count = wire - COMPANION_PROTOCOL_LIST_WIRE_OFFSET;
        return count < 0 ? 0 : count;
      }
      """
    else
      ""
    end
  end

  defp companion_protocol_uses_boxed_dispatch?(schema) do
    Enum.any?(schema.phone_to_watch, &(not native_int_payload_message?(&1)))
  end

  defp c_dispatch_case(msg, phone_to_watch_tag) do
    if native_int_payload_message?(msg) do
      values =
        msg.fields
        |> Enum.with_index()
        |> Enum.map_join(", ", fn {field, index} -> c_native_int_value_expr(field, index) end)

      values_decl =
        case msg.fields do
          [] -> ""
          _ -> "      const int64_t payload_values[] = { #{values} };\n"
        end

      values_ref = if msg.fields == [], do: "NULL", else: "payload_values"

      """
          case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_#{macro_name(msg.name)}: {
            if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      #{values_decl}      return elmc_pebble_dispatch_tag_int_values(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, #{phone_to_watch_tag}, #{length(msg.fields)}, #{values_ref});
          }
      """
    else
      payload = c_payload_expr(msg)

      """
          case COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_#{macro_name(msg.name)}: {
            if (ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET <= 0) return -7;
      #{payload}
            if (!payload) return -2;
            ElmcValue *phone_to_watch = companion_protocol_new_phone_to_watch_message(#{phone_to_watch_tag}, payload);
            elmc_release(payload);
            if (!phone_to_watch) return -2;
            int rc = elmc_pebble_dispatch_tag_payload(app, ELMC_PEBBLE_MSG_PHONE_TO_WATCH_TARGET, phone_to_watch);
            elmc_release(phone_to_watch);
            return rc;
          }
      """
    end
  end

  defp native_int_payload_message?(%{fields: fields}) do
    Enum.all?(fields, fn
      %{wire_type: :int} -> true
      %{wire_type: {:enum, _type}} -> true
      _field -> false
    end)
  end

  defp c_native_int_value_expr(%{wire_type: {:enum, type}}, index),
    do: "#{c_runtime_tag_function(type)}(message->int_fields[#{index}])"

  defp c_native_int_value_expr(_field, index), do: "message->int_fields[#{index}]"

  defp js_payload_key(name), do: "String(constants.KEY_#{macro_name(name)})"

  defp js(schema) do
    constants =
      schema.key_ids
      |> Enum.sort_by(fn {_name, id} -> id end)
      |> Enum.map_join("\n", fn {name, id} -> "  KEY_#{macro_name(name)}: #{id}," end)

    enum_maps =
      schema.enums
      |> Enum.map_join("\n\n", fn {type, ctors} ->
        entries =
          ctors
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {ctor, index} -> "  #{wire_code(index)}: \"#{ctor}\"," end)

        "var #{macro_name(type)}_BY_CODE = {\n#{entries}\n};"
      end)

    enum_lookup =
      schema.enums
      |> Enum.map_join("\n", fn {type, _ctors} ->
        """
        function #{camel_lower(type)}NameForCode(code) {
          return Object.prototype.hasOwnProperty.call(#{macro_name(type)}_BY_CODE, code)
            ? #{macro_name(type)}_BY_CODE[code]
            : null;
        }
        """
      end)

    w2p_cases =
      schema.watch_to_phone
      |> Enum.map_join("\n", fn msg ->
        field_props =
          msg.fields
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {field, index} ->
            js_field_prop(field, index)
          end)

        """
            case #{msg.tag}:
              return {
                kind: "#{msg.name}"#{if field_props == "", do: "", else: ",\n" <> field_props}
              };
        """
      end)

    p2w_cases =
      schema.phone_to_watch
      |> Enum.map_join("\n", fn msg ->
        writes =
          msg.fields
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {field, index} ->
            source = if index == 0, do: "value", else: "fields && fields.#{field.name}"
            js_encode_field_writes(field, source)
          end)

        """
            case "#{msg.name}":
              payload[#{js_payload_key("message_tag")}] = #{msg.tag};
        #{writes}
              return payload;
        """
      end)

    exports =
      schema.enums
      |> Map.keys()
      |> Enum.map_join("\n", fn type ->
        "exported.#{camel_lower(type)}NameForCode = #{camel_lower(type)}NameForCode;"
      end)

    """
    var constants = {
    #{constants}
    };

    #{enum_maps}

    #{enum_lookup}

    function encodeListIntField(prefix, list) {
      var items = Array.isArray(list) ? list : [];
      if (items.length > #{@list_max_elements}) {
        items = items.slice(0, #{@list_max_elements});
      }
      payload[constants["KEY_" + prefix.toUpperCase() + "_COUNT"]] = items.length + #{@wire_code_base};
      for (var i = 0; i < items.length; i++) {
        payload[constants["KEY_" + prefix.toUpperCase() + "_" + i]] = items[i] + #{@wire_code_base};
      }
    }

    function decodeWatchToPhonePayload(payload) {
      if (!payload) {
        return null;
      }

      var tag = payload[#{js_payload_key("message_tag")}];
      if (typeof tag !== "number") {
        return null;
      }

      switch (tag) {
    #{w2p_cases}
        default:
          return null;
      }
    }

    function encodePhoneToWatchPayload(kind, value, fields) {
      var payload = {};

      switch (kind) {
    #{p2w_cases}
        default:
          return null;
      }
    }

    var exported = constants;
    #{exports}
    exported.decodeWatchToPhonePayload = decodeWatchToPhonePayload;
    exported.encodePhoneToWatchPayload = encodePhoneToWatchPayload;
    module.exports = exported;
    """
  end

  defp elm_internal(schema) do
    """
    module Companion.Internal exposing
        ( decodeWatchToPhonePayload
        , encodePhoneToWatch
        , watchToPhoneTag
        , watchToPhoneValue
        )

    {-| Generated wire encoding and decoding helpers for companion messages.

    This module is derived from `Companion.Types`; edit the protocol types rather
    than this file.
    -}

    import Companion.Types exposing (..)
    import Json.Decode as Decode
    import Json.Encode as Encode


    #{elm_list_helpers()}

    #{elm_enum_helpers(schema)}

    #{elm_payload_union_helpers(schema)}

    decodeWatchToPhonePayload : Decode.Value -> Result String WatchToPhone
    decodeWatchToPhonePayload value =
        Decode.decodeValue (Decode.field "message_tag" Decode.int) value
            |> Result.mapError Decode.errorToString
            |> Result.andThen
                (\\tag ->
                    case tag of
    #{elm_decode_cases(schema, schema.watch_to_phone)}
                        _ ->
                            Err ("Unknown message_tag: " ++ String.fromInt tag)
                )


    encodePhoneToWatch : PhoneToWatch -> Encode.Value
    encodePhoneToWatch msg =
        case msg of
    #{elm_encode_cases(schema, schema.phone_to_watch)}

    watchToPhoneTag : WatchToPhone -> Int
    watchToPhoneTag message =
        case message of
    #{elm_tag_cases(schema.watch_to_phone)}

    watchToPhoneValue : WatchToPhone -> Int
    watchToPhoneValue message =
        case message of
    #{elm_value_cases(schema, schema.watch_to_phone)}
    """
  end

  defp elm_decode_cases(schema, messages) do
    Enum.map_join(messages, "\n", fn msg ->
      case msg.fields do
        [] ->
          "                    #{msg.tag} ->\n                        Ok #{msg.name}\n"

        [field] ->
          key = field.key

          "                    #{msg.tag} ->\n" <>
            "                        Decode.decodeValue (Decode.field \"#{key}\" #{elm_decoder(field)}) value\n" <>
            "                            |> Result.mapError Decode.errorToString\n" <>
            "                            |> Result.andThen\n" <>
            "                                (\\field1 ->\n" <>
            "                                    #{elm_decode_constructor(schema, msg.name, field, "field1")}\n" <>
            "                                )\n"

        fields ->
          decoder =
            fields
            |> Enum.reduce(nil, fn field, acc ->
              part = "(Decode.field \"#{field.key}\" #{elm_decoder(field)})"

              if is_nil(acc) do
                part
              else
                "Decode.map2 Tuple.pair #{acc} #{part}"
              end
            end)

          "                    #{msg.tag} ->\n" <>
            "                        Decode.decodeValue #{decoder} value\n" <>
            "                            |> Result.mapError Decode.errorToString\n" <>
            "                            |> Result.andThen\n" <>
            "                                (\\fields ->\n" <>
            "                                    #{elm_decode_tuple_constructor(schema, msg.name, fields, 1, "fields")}\n" <>
            "                                )\n"
      end
    end)
  end

  defp elm_encode_cases(schema, messages) do
    Enum.map_join(messages, "\n", fn msg ->
      args = elm_pattern_args(msg.fields)
      scalar_fields = elm_encode_scalar_fields(schema, msg.fields)
      list_fields = elm_encode_list_field_appends(msg.fields)
      closing = if list_fields == "", do: " ])", else: " ]#{list_fields})"

      """
              #{msg.name}#{args} ->
                  Encode.object
                      ([ ( "message_tag", Encode.int #{msg.tag} )#{scalar_fields}#{closing}
      """
    end)
  end

  defp elm_encode_scalar_fields(schema, fields) do
    fields
    |> Enum.with_index(1)
    |> Enum.reject(fn {field, _} -> match?(%{wire_type: {:list, :int}}, field) end)
    |> Enum.map_join("", fn {field, index} ->
      elm_encode_object_field(schema, field, "field#{index}")
    end)
  end

  defp elm_encode_list_field_appends(fields) do
    fields
    |> Enum.with_index(1)
    |> Enum.filter(fn {field, _} -> match?(%{wire_type: {:list, :int}}, field) end)
    |> Enum.map_join("", fn {field, index} ->
      "\n                        ++ encodeListInt \"#{field.key}\" field#{index}"
    end)
  end

  defp elm_tag_cases(messages) do
    Enum.map_join(messages, "\n", fn msg ->
      "        #{msg.name}#{elm_ignore_pattern_args(msg.fields)} ->\n            #{msg.tag}\n"
    end)
  end

  defp elm_pattern_args(fields) do
    fields
    |> Enum.with_index(1)
    |> Enum.map_join("", fn {_field, index} -> " field#{index}" end)
  end

  defp elm_ignore_pattern_args([]), do: ""

  defp elm_ignore_pattern_args(fields) do
    fields
    |> Enum.map_join("", fn _field -> " _" end)
  end

  defp elm_value_cases(schema, messages) do
    Enum.map_join(messages, "\n", fn msg ->
      case msg.fields do
        [] ->
          "        #{msg.name} ->\n            0\n"

        [field] ->
          "        #{msg.name} field1 ->\n            #{elm_encode_value(schema, field, "field1")}\n"

        fields ->
          "        #{msg.name}#{elm_ignore_pattern_args(fields)} ->\n            0\n"
      end
    end)
  end

  defp elm_decode_constructor(_schema, name, %{wire_type: {:enum, _type}, type: type}, value) do
    """
    case #{elm_enum_decode_name(type)} #{value} of
                                                Just decodedField1 ->
                                                    Ok (#{name} decodedField1)

                                                Nothing ->
                                                    Err ("Unknown #{type} code: " ++ String.fromInt #{value})
    """
  end

  defp elm_decode_constructor(_schema, name, _field, value), do: "Ok (#{name} #{value})"

  defp elm_decode_tuple_constructor(schema, name, fields, index, source) do
    case fields do
      [] ->
        "Ok #{name}"

      [field] ->
        elm_decode_constructor(schema, name, field, source)

      [_field | rest] ->
        current = "field#{index}"
        next_source = "rest#{index}"

        """
        let
                                      ( #{current}, #{next_source} ) =
                                          #{source}
                                  in
                                  #{elm_decode_tuple_constructor(schema, name, rest, index + 1, next_source)}
        """
    end
  end

  defp elm_encode_object_field(_schema, %{wire_type: {:union, type}, key: key}, value) do
    "\n                , ( \"#{key}_tag\", Encode.int (#{elm_union_tag_encode_name(type)} #{value}) )" <>
      "\n                , ( \"#{key}_value\", Encode.int (#{elm_union_value_encode_name(type)} #{value}) )"
  end

  defp elm_encode_object_field(schema, field, value) do
    "\n                , ( \"#{field.key}\", #{elm_encoder(schema, field, value)} )"
  end

  defp elm_decoder(%{wire_type: :bool}),
    do:
      "(Decode.andThen (\\value -> if value == #{@wire_true_code} then Decode.succeed True else if value == #{@wire_false_code} then Decode.succeed False else Decode.fail \"Invalid bool wire code\") Decode.int)"

  defp elm_decoder(%{wire_type: :string}), do: "Decode.string"
  defp elm_decoder(%{wire_type: {:list, :int}, key: key}), do: "decodeListInt \"#{key}\""
  defp elm_decoder(_field), do: "Decode.int"

  defp elm_encoder(_schema, %{wire_type: :bool}, value),
    do: "Encode.int (#{elm_encode_value(%{}, %{wire_type: :bool}, value)})"

  defp elm_encoder(_schema, %{wire_type: :string}, value), do: "Encode.string #{value}"

  defp elm_encoder(schema, %{wire_type: {:enum, _type}} = field, value),
    do: "Encode.int (#{elm_encode_value(schema, field, value)})"

  defp elm_encoder(_schema, %{wire_type: {:union, type}}, value),
    do: "Encode.int (#{elm_union_tag_encode_name(type)} #{value})"

  defp elm_encoder(_schema, _field, value), do: "Encode.int #{value}"

  defp elm_encode_value(_schema, %{wire_type: :bool}, value),
    do: "if #{value} then #{@wire_true_code} else #{@wire_false_code}"

  defp elm_encode_value(_schema, %{wire_type: {:enum, _type}, type: type}, value),
    do: "#{elm_enum_encode_name(type)} #{value}"

  defp elm_encode_value(_schema, %{wire_type: {:union, type}}, value),
    do: "#{elm_union_tag_encode_name(type)} #{value}"

  defp elm_encode_value(_schema, _field, value), do: value

  defp elm_list_helpers do
    """
    decodeListInt : String -> Decode.Decoder (List Int)
    decodeListInt prefix =
        Decode.field (prefix ++ "_count") Decode.int
            |> Decode.andThen
                (\\wireCount ->
                    let
                        count =
                            wireCount - #{@wire_code_base}
                    in
                    if count < 0 then
                        Decode.fail "Invalid list count"
                    else
                        decodeListIntElements prefix count 0 []
                )


    decodeListIntElements : String -> Int -> Int -> List Int -> Decode.Decoder (List Int)
    decodeListIntElements prefix remaining index acc =
        if remaining <= 0 then
            Decode.succeed (List.reverse acc)
        else
            Decode.oneOf
                [ Decode.field (prefix ++ "_" ++ String.fromInt index) Decode.int
                    |> Decode.map (\\wire -> wire - #{@wire_code_base})
                , Decode.succeed 0
                ]
                |> Decode.andThen
                    (\\value ->
                        decodeListIntElements prefix (remaining - 1) (index + 1) (value :: acc)
                    )


    encodeListInt : String -> List Int -> List ( String, Encode.Value )
    encodeListInt prefix list =
        let
            items =
                if List.length list > #{@list_max_elements} then
                    List.take #{@list_max_elements} list
                else
                    list
        in
        ( prefix ++ "_count", Encode.int (List.length items + #{@wire_code_base}) )
            :: List.indexedMap
                (\\index value ->
                    ( prefix ++ "_" ++ String.fromInt index, Encode.int (value + #{@wire_code_base}) )
                )
                items
    """
  end

  defp elm_enum_helpers(%{enums: enums}) do
    enums
    |> Enum.map_join("\n\n", fn {type, _ctors} ->
      """
      #{elm_enum_encode_name(type)} : #{type} -> Int
      #{elm_enum_encode_name(type)} value =
          case value of
      #{elm_enum_to_code_branches(%{enums: enums}, type)}


      #{elm_enum_decode_name(type)} : Int -> Maybe #{type}
      #{elm_enum_decode_name(type)} value =
          case value of
      #{elm_enum_from_code_branches(%{enums: enums}, type)}
      """
    end)
  end

  defp elm_payload_union_helpers(%{payload_unions: payload_unions}) do
    payload_unions
    |> Enum.map_join("\n\n", fn {type, ctors} ->
      """
      #{elm_union_tag_encode_name(type)} : #{type} -> Int
      #{elm_union_tag_encode_name(type)} value =
          case value of
      #{elm_union_tag_branches(ctors)}


      #{elm_union_value_encode_name(type)} : #{type} -> Int
      #{elm_union_value_encode_name(type)} value =
          case value of
      #{elm_union_value_branches(ctors)}


      #{elm_union_decode_name(type)} : Int -> Int -> Maybe #{type}
      #{elm_union_decode_name(type)} tag value =
          case tag of
      #{elm_union_decode_branches(ctors)}
      """
    end)
  end

  defp elm_enum_encode_name(type), do: "encode#{type}Code"
  defp elm_enum_decode_name(type), do: "decode#{type}Code"
  defp elm_union_tag_encode_name(type), do: "encode#{type}Tag"
  defp elm_union_value_encode_name(type), do: "encode#{type}Value"
  defp elm_union_decode_name(type), do: "decode#{type}"

  defp elm_union_tag_branches(ctors) do
    ctors
    |> Enum.with_index()
    |> Enum.map_join("\n\n", fn {ctor, index} ->
      "        #{ctor.name}#{elm_union_pattern_args(ctor.args)} ->\n            #{wire_code(index)}"
    end)
  end

  defp elm_union_value_branches(ctors) do
    ctors
    |> Enum.map_join("\n\n", fn ctor ->
      "        #{ctor.name}#{elm_union_pattern_args(ctor.args)} ->\n            #{elm_union_value_expr(ctor.args)}"
    end)
  end

  defp elm_union_decode_branches(ctors) do
    known =
      ctors
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn {ctor, index} ->
        "        #{wire_code(index)} ->\n            #{elm_union_decode_expr(ctor)}"
      end)

    known <> "\n\n        _ ->\n            Nothing"
  end

  defp elm_union_pattern_args([]), do: ""
  defp elm_union_pattern_args([_arg]), do: " field1"
  defp elm_union_pattern_args(args), do: Enum.map_join(args, "", fn _ -> " _" end)

  defp elm_union_value_expr([]), do: "0"
  defp elm_union_value_expr([_arg]), do: "field1"
  defp elm_union_value_expr(_args), do: "0"

  defp elm_union_decode_expr(%{name: name, args: []}), do: "Just #{name}"
  defp elm_union_decode_expr(%{name: name, args: [_arg]}), do: "Just (#{name} value)"
  defp elm_union_decode_expr(_ctor), do: "Nothing"

  defp elm_enum_to_code_branches(schema, type) do
    schema.enums
    |> Map.fetch!(type)
    |> Enum.with_index()
    |> Enum.map_join("\n\n", fn {ctor, index} ->
      "        #{ctor} ->\n            #{wire_code(index)}"
    end)
  end

  defp elm_enum_from_code_branches(schema, type) do
    known =
      schema.enums
      |> Map.fetch!(type)
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn {ctor, index} ->
        "        #{wire_code(index)} ->\n            Just #{ctor}"
      end)

    known <> "\n\n        _ ->\n            Nothing"
  end

  defp c_write_tuple(nil, _key_ids), do: ""

  defp c_write_tuple(field, _key_ids) do
    key_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(field.key)}"

    case field.wire_type do
      :string -> "      dict_write_cstring(iter, #{key_macro}, \"\");"
      _ -> "      dict_write_int32(iter, #{key_macro}, value);"
    end
  end

  defp c_required_field_expr(%{wire_type: {:union, _type}}, index),
    do: "decoder->saw_fields[#{index}] && decoder->saw_union_value_fields[#{index}]"

  defp c_required_field_expr(%{wire_type: {:list, :int}}, index),
    do: "decoder->saw_list_counts[#{index}]"

  defp c_required_field_expr(_field, index), do: "decoder->saw_fields[#{index}]"

  # Treat missing enum/union tag fields as the first 1-based wire code when AppMessage omits keys.
  defp c_missing_field_defaults(%{fields: fields}) do
    fields
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {field, index} ->
      c_missing_field_default(field, index)
    end)
  end

  defp c_missing_field_default(%{wire_type: {:union, _type}}, index) do
    """
          if (!decoder->saw_fields[#{index}]) {
            decoder->saw_fields[#{index}] = true;
            decoder->message.int_fields[#{index}] = #{@wire_code_base};
          }
          if (!decoder->saw_union_value_fields[#{index}]) {
            decoder->saw_union_value_fields[#{index}] = true;
            decoder->message.union_value_fields[#{index}] = 0;
          }
    """
  end

  defp c_missing_field_default(%{wire_type: :bool}, index) do
    """
          if (!decoder->saw_fields[#{index}]) {
            decoder->saw_fields[#{index}] = true;
            decoder->message.bool_fields[#{index}] = false;
          }
    """
  end

  defp c_missing_field_default(%{wire_type: :int}, index) do
    c_missing_int_field_default(index)
  end

  defp c_missing_field_default(%{wire_type: {:enum, _type}}, index) do
    c_missing_tag_field_default(index)
  end

  defp c_missing_field_default(%{wire_type: {:list, :int}}, index) do
    missing_elements =
      0..(@list_max_elements - 1)
      |> Enum.map_join("\n", fn elem_index ->
        """
              if (!decoder->saw_list_elements[#{index}][#{elem_index}]) {
                decoder->saw_list_elements[#{index}][#{elem_index}] = true;
                decoder->message.list_values[#{index}][#{elem_index}] = 0;
              }
        """
      end)

    """
          if (!decoder->saw_list_counts[#{index}]) {
            decoder->saw_list_counts[#{index}] = true;
            decoder->message.list_counts[#{index}] = 0;
          }
    #{missing_elements}
    """
  end

  defp c_missing_field_default(_field, _index), do: ""

  defp c_missing_tag_field_default(index) do
    """
          if (!decoder->saw_fields[#{index}]) {
            decoder->saw_fields[#{index}] = true;
            decoder->message.int_fields[#{index}] = #{@wire_code_base};
          }
    """
  end

  defp c_missing_int_field_default(index) do
    """
          if (!decoder->saw_fields[#{index}]) {
            decoder->saw_fields[#{index}] = true;
            decoder->message.int_fields[#{index}] = 0;
          }
    """
  end

  defp c_decode_tuple_cases(%{wire_type: {:list, :int}, key: key}, index) do
    count_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(key <> "_count")}"

    count_case = """
      if (tuple->key == #{count_macro}) {
        decoder->saw_list_counts[#{index}] = true;
        if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
          decoder->message.list_counts[#{index}] =
              companion_protocol_decode_list_wire_count(tuple->value->int32);
        }
        return;
      }
    """

    element_cases =
      0..(@list_max_elements - 1)
      |> Enum.map_join("\n", fn elem_index ->
        elem_macro = "COMPANION_PROTOCOL_KEY_#{macro_name("#{key}_#{elem_index}")}"

        """
          if (tuple->key == #{elem_macro}) {
            decoder->saw_list_elements[#{index}][#{elem_index}] = true;
            if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
              decoder->message.list_values[#{index}][#{elem_index}] =
                  companion_protocol_decode_list_wire_int(tuple->value->int32);
            }
            return;
          }
        """
      end)

    count_case <> element_cases
  end

  defp c_decode_tuple_cases(%{wire_type: {:union, _type}} = field, index) do
    tag_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(field.key <> "_tag")}"
    value_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(field.key <> "_value")}"

    """
      if (tuple->key == #{tag_macro}) {
        decoder->saw_fields[#{index}] = true;
        if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
          decoder->message.int_fields[#{index}] = tuple->value->int32;
        }
        return;
      }

      if (tuple->key == #{value_macro}) {
        decoder->saw_union_value_fields[#{index}] = true;
        if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
          decoder->message.union_value_fields[#{index}] = tuple->value->int32;
        }
        return;
      }
    """
  end

  defp c_decode_tuple_cases(field, index) do
    key_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(field.key)}"

    """
      if (tuple->key == #{key_macro}) {
        decoder->saw_fields[#{index}] = true;
    #{c_decode_tuple_field(field, index)}
        return;
      }
    """
  end

  defp c_decode_tuple_field(%{wire_type: :string}, index) do
    """
      if (tuple->type == TUPLE_CSTRING) {
        strncpy(decoder->message.string_fields[#{index}], tuple->value->cstring, 63);
        decoder->message.string_fields[#{index}][63] = '\\0';
      }
    """
  end

  defp c_decode_tuple_field(%{wire_type: :bool}, index) do
    """
      if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
        decoder->message.bool_fields[#{index}] = tuple->value->int32 == #{@wire_true_code};
      }
    """
  end

  defp c_decode_tuple_field(_field, index) do
    """
      if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
        decoder->message.int_fields[#{index}] = tuple->value->int32;
      }
    """
  end

  defp c_payload_expr(%{fields: []}), do: "      ElmcValue *payload = elmc_new_int(0);"

  defp c_payload_expr(%{fields: [field]}) do
    "      ElmcValue *payload = #{c_value_expr(field, 0)};"
  end

  defp c_payload_expr(%{fields: fields}) do
    vars =
      fields
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {field, index} ->
        "      ElmcValue *field_#{index} = #{c_value_expr(field, index)};"
      end)

    tuple =
      0..(length(fields) - 1)
      |> Enum.map(&"field_#{&1}")
      |> c_tuple_chain()

    releases =
      0..(length(fields) - 1)
      |> Enum.map_join("\n", &"      elmc_release(field_#{&1});")

    """
    #{vars}
          ElmcValue *payload = #{tuple};
    #{releases}
    """
  end

  defp c_value_expr(%{wire_type: :string}, index),
    do: "elmc_new_string(message->string_fields[#{index}])"

  defp c_value_expr(%{wire_type: :bool}, index),
    do: "elmc_new_bool(message->bool_fields[#{index}] ? 1 : 0)"

  defp c_value_expr(%{wire_type: {:enum, type}}, index),
    do: "elmc_new_int(#{c_runtime_tag_function(type)}(message->int_fields[#{index}]))"

  defp c_value_expr(%{wire_type: {:union, type}}, index),
    do:
      "companion_protocol_new_union_value(#{c_runtime_tag_function(type)}(message->int_fields[#{index}]), message->union_value_fields[#{index}])"

  defp c_value_expr(%{wire_type: {:list, :int}}, index),
    do:
      "elmc_list_from_int_array(message->list_values[#{index}], message->list_counts[#{index}])"

  defp c_value_expr(_field, index), do: "elmc_new_int(message->int_fields[#{index}])"

  defp c_runtime_tag_helpers(schema, runtime_tags) do
    schema
    |> c_runtime_tag_types()
    |> Enum.map_join("\n\n", fn {type, ctors} ->
      cases =
        ctors
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {ctor, wire_code} ->
          runtime_tag =
            runtime_tags
            |> Map.get(type, %{})
            |> Map.get(ctor, wire_code)

          "    case #{wire_code}: return #{runtime_tag};"
        end)

      """
      static int32_t #{c_runtime_tag_function(type)}(int32_t wire_code) {
        switch (wire_code) {
      #{cases}
          default: return 0;
        }
      }
      """
    end)
  end

  defp c_runtime_tag_types(schema) do
    used_types =
      schema.phone_to_watch
      |> Enum.flat_map(& &1.fields)
      |> Enum.flat_map(fn
        %{wire_type: {:enum, type}} -> [{:enum, type}]
        %{wire_type: {:union, type}} -> [{:union, type}]
        _ -> []
      end)
      |> Enum.uniq()

    enum_type_names = for {:enum, type} <- used_types, do: type

    union_type_names = for {:union, type} <- used_types, do: type

    enum_types = Map.take(schema.enums, enum_type_names)

    payload_union_types =
      schema.payload_unions
      |> Map.take(union_type_names)
      |> Map.new(fn {type, ctors} -> {type, Enum.map(ctors, & &1.name)} end)

    Map.merge(enum_types, payload_union_types)
  end

  defp c_runtime_tag_function(type),
    do: "companion_protocol_runtime_tag_#{macro_name(type)}"

  defp c_tuple_chain([single]), do: single
  defp c_tuple_chain([head | rest]), do: "elmc_tuple2(#{head}, #{c_tuple_chain(rest)})"

  defp js_field_prop(%{wire_type: {:enum, type}, key: key, name: name}, _index) do
    code = "payload[#{js_payload_key(key)}]"

    "    #{name}Code: #{code},\n    #{camel_lower(type)}Name: #{camel_lower(type)}NameForCode(#{code})"
  end

  defp js_field_prop(%{wire_type: {:union, _type}, key: key, name: name}, _index) do
    tag = "payload[#{js_payload_key(key <> "_tag")}]"
    value = "payload[#{js_payload_key(key <> "_value")}]"

    "    #{name}: { tag: #{tag}, value: #{value} }"
  end

  defp js_field_prop(%{wire_type: {:list, :int}, key: key, name: name}, _index) do
    element_reads =
      0..(@list_max_elements - 1)
      |> Enum.map_join("\n", fn i ->
        "      var wire#{i} = payload[#{js_payload_key("#{key}_#{i}")}];"
      end)

    wire_refs =
      0..(@list_max_elements - 1)
      |> Enum.map_join(", ", &"wire#{&1}")

    "    #{name}: (function () {\n" <>
      "      var countWire = payload[#{js_payload_key(key <> "_count")}];\n" <>
      "      var count = typeof countWire === \"number\" ? Math.max(0, countWire - #{@wire_code_base}) : 0;\n" <>
      "      if (count > #{@list_max_elements}) count = #{@list_max_elements};\n" <>
      element_reads <>
      "\n      var out = [];\n" <>
      "      for (var i = 0; i < count; i++) {\n" <>
      "        var wire = [#{wire_refs}][i];\n" <>
      "        out.push(typeof wire === \"number\" ? wire - #{@wire_code_base} : 0);\n" <>
      "      }\n" <>
      "      return out;\n" <>
      "    })()"
  end

  defp js_field_prop(%{key: key, name: name}, _index) do
    "    #{name}: payload[#{js_payload_key(key)}]"
  end

  defp js_encode_field_writes(%{wire_type: {:union, _type}} = field, source) do
    tag_key = js_payload_key(field.key <> "_tag")
    value_key = js_payload_key(field.key <> "_value")

    """
          payload[#{tag_key}] = #{source} && #{source}.tag;
          payload[#{value_key}] = #{source} && #{source}.value;
    """
  end

  defp js_encode_field_writes(%{wire_type: {:list, :int}, key: key}, source) do
    "      encodeListIntField(#{js_string_key_macro(key)}, #{source});"
  end

  defp js_encode_field_writes(field, source) do
    "      payload[#{js_payload_key(field.key)}] = #{js_encode_field_value(field, source)};"
  end

  defp js_string_key_macro(key), do: "\"#{key}\""

  defp js_encode_field_value(%{wire_type: :bool}, source),
    do: "(#{source} ? #{@wire_true_code} : #{@wire_false_code})"

  defp js_encode_field_value(_field, source), do: source

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

  defp camel_lower(value) do
    value
    |> to_string()
    |> case do
      "" -> ""
      <<first::binary-size(1), rest::binary>> -> String.downcase(first) <> rest
    end
  end
end
