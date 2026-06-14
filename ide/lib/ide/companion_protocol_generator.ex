defmodule Ide.CompanionProtocolGenerator do
  @moduledoc false

  alias Ide.Debugger.Protocol.Schema
  alias Ide.CompanionProtocol.TypeParse
  alias Ide.CompanionProtocol.WireFlatten
  alias Ide.CompanionProtocol.WireSchema

  @type schema :: Schema.t()
  @type constructor :: Schema.constructor()
  @type message :: Schema.message()
  @type field :: Schema.field()

  @type generator_error ::
          {:missing_union, String.t()}
          | {:wire_schema_too_large, WireSchema.wire_schema_too_large_detail()}
          | File.posix()

  # Pebble AppMessage commonly drops dictionary entries whose value is zero.
  # Enum and union-tag wire codes therefore start at 1; bool uses 1=true, 2=false.
  @wire_code_base 1
  @wire_true_code 1
  @wire_false_code 2
  @list_max_elements 16
  @dict_max_entries 16

  @spec wire_code_base() :: pos_integer()
  def wire_code_base, do: @wire_code_base

  @spec wire_code(non_neg_integer()) :: pos_integer()
  defp wire_code(index) when is_integer(index), do: index + @wire_code_base

  @spec generate(String.t(), String.t(), String.t(), String.t(), generate_opts()) ::
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
          {:ok, WireSchema.key_ids()} | {:error, generator_error()}
  def message_keys(types_elm) do
    with {:ok, source} <- File.read(types_elm),
         {:ok, schema} <- schema_from_source(source) do
      {:ok, schema.key_ids}
    end
  end

  @spec schema_from_source(String.t()) :: {:ok, schema()} | {:error, generator_error()}
  def schema_from_source(source) when is_binary(source) do
    unions = TypeParse.parse_unions(source)
    type_aliases = TypeParse.parse_type_aliases(source)
    enums = enum_unions(unions, ["WatchToPhone", "PhoneToWatch"])
    payload_unions = payload_unions(unions, enums, ["WatchToPhone", "PhoneToWatch"])

    base_schema = %{enums: enums, payload_unions: payload_unions, type_aliases: type_aliases}

    with {:ok, watch_to_phone} <-
           message_union(unions, base_schema, "WatchToPhone", 2),
         {:ok, phone_to_watch} <-
           message_union(unions, base_schema, "PhoneToWatch", 201) do
      messages = watch_to_phone ++ phone_to_watch

      schema_without_keys = %{
        enums: enums,
        payload_unions: payload_unions,
        type_aliases: type_aliases,
        watch_to_phone: watch_to_phone,
        phone_to_watch: phone_to_watch,
        wire_slots: []
      }

      with :ok <- WireFlatten.validate_message_key_count(messages, schema_without_keys) do
        wire_slots =
          messages
          |> Enum.flat_map(fn message ->
            message.fields
            |> Enum.flat_map(&WireFlatten.slots_for_field(&1, schema_without_keys))
            |> Enum.map(&Map.put(&1, :message, message.name))
          end)

        key_names =
          ["message_tag"] ++
            (messages
             |> Enum.flat_map(&WireFlatten.message_keys(&1, schema_without_keys))
             |> Enum.uniq())

        key_ids =
          key_names
          |> Enum.with_index(10)
          |> Map.new(fn {name, id} -> {name, id} end)

        {:ok,
         %{
           enums: enums,
           payload_unions: payload_unions,
           type_aliases: type_aliases,
           watch_to_phone: watch_to_phone,
           phone_to_watch: phone_to_watch,
           wire_slots: wire_slots,
           key_ids: key_ids
         }}
      end
    end
  end

  @spec enum_unions(
          %{optional(String.t()) => [constructor()]},
          [String.t()]
        ) :: WireSchema.enums()
  defp enum_unions(unions, excluded) do
    unions
    |> Enum.reject(fn {name, _} -> name in excluded end)
    |> Enum.filter(fn {_name, ctors} -> Enum.all?(ctors, &(Map.get(&1, :args, []) == [])) end)
    |> Map.new(fn {name, ctors} -> {name, Enum.map(ctors, & &1.name)} end)
  end

  @spec payload_unions(
          %{optional(String.t()) => [constructor()]},
          WireSchema.enums(),
          [String.t()]
        ) :: WireSchema.payload_unions()
  defp payload_unions(unions, enums, excluded) do
    unions
    |> Enum.reject(fn {name, _} -> name in excluded or Map.has_key?(enums, name) end)
    |> Map.new()
  end

  @spec message_union(
          %{optional(String.t()) => [constructor()]},
          WireSchema.type_resolution_context(),
          String.t(),
          pos_integer()
        ) :: {:ok, [message()]} | {:error, {:missing_union, String.t()}}
  defp message_union(unions, schema, name, first_tag) do
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
                  wire_type:
                    WireFlatten.resolve_type(
                      type,
                      schema.enums,
                      schema.payload_unions,
                      schema.type_aliases
                    )
                }
              end)

            %{name: ctor.name, tag: tag, fields: fields}
          end)

        {:ok, messages}

      :error ->
        {:error, {:missing_union, name}}
    end
  end

  @spec header(schema()) :: String.t()
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
    wire_struct_fields = c_wire_struct_fields(schema)
    wire_seen_fields = c_wire_seen_fields(schema)

    message_fields =
      [
        "  CompanionProtocolPhoneToWatchKind kind;",
        "  int32_t int_fields[COMPANION_PROTOCOL_MAX_FIELDS];",
        "  CompanionProtocolPhoneToWatchWire wire;"
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
        ) ++
        wire_seen_fields

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
    #{Enum.join(wire_struct_fields, "\n")}
    } CompanionProtocolPhoneToWatchWire;

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

  @type generate_opts :: [runtime_tags: WireSchema.runtime_tags()]

  @spec source(schema(), generate_opts()) :: String.t()
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

    wire_push_cases = c_decode_wire_slot_cases(schema)

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

    composite_build_helpers = c_composite_build_helpers(schema)

    union_value_helper =
      if companion_protocol_uses_union_payloads?(schema) do
        """
        static ElmcValue *companion_protocol_new_union_value(int32_t runtime_tag, int32_t value) {
          ElmcValue *tag_value = elmc_new_int_take(runtime_tag);
          ElmcValue *payload_value = elmc_new_int_take(value);
          if (!tag_value || !payload_value) {
            if (tag_value) elmc_release(tag_value);
            if (payload_value) elmc_release(payload_value);
            return NULL;
          }

          return elmc_tuple2_take_value(tag_value, payload_value);
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
          ElmcValue *tag_value = elmc_new_int_take(tag);
          if (!tag_value) return NULL;

          return elmc_tuple2_take_value(tag_value, payload);
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

    #{composite_build_helpers}

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
      memset(decoder, 0, sizeof(*decoder));
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
    #{wire_push_cases}
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

  @spec companion_protocol_uses_union_payloads?(schema()) :: boolean()
  defp companion_protocol_uses_union_payloads?(schema) do
    schema_fields(schema)
    |> Enum.any?(fn
      %{wire_type: {:union, _type}} -> true
      _field -> false
    end)
  end

  @spec companion_protocol_uses_list_payloads?(schema()) :: boolean()
  defp companion_protocol_uses_list_payloads?(schema) do
    schema_fields(schema)
    |> Enum.any?(fn
      %{wire_type: {:list, _elem}} -> true
      _field -> false
    end)
  end

  @spec companion_protocol_uses_payload_type?(schema(), WireSchema.wire_type()) :: boolean()
  defp companion_protocol_uses_payload_type?(schema, wire_type) do
    schema_fields(schema)
    |> Enum.any?(&(&1.wire_type == wire_type))
  end

  @spec schema_fields(schema()) :: [field()]
  defp schema_fields(schema) do
    (schema.watch_to_phone ++ schema.phone_to_watch)
    |> Enum.flat_map(& &1.fields)
  end

  defp optional_c_struct_field(true, field), do: [field]
  defp optional_c_struct_field(false, _field), do: []

  @spec c_wire_struct_fields(schema()) :: [String.t()]
  defp c_wire_struct_fields(schema) do
    fields =
      schema.wire_slots
      |> Enum.uniq_by(& &1.c_name)
      |> Enum.map(fn
        %{storage_type: :string, c_name: c_name} -> "  char #{c_name}[64];"
        %{storage_type: :bool, c_name: c_name} -> "  bool #{c_name};"
        %{c_name: c_name} -> "  int32_t #{c_name};"
      end)

    if fields == [], do: ["  int unused;"], else: fields
  end

  defp c_wire_seen_fields(schema) do
    schema.wire_slots
    |> Enum.uniq_by(& &1.c_name)
    |> Enum.map(fn %{c_name: c_name} -> "  bool saw_#{c_name};" end)
  end

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

  @spec js(schema()) :: String.t()
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

    function encodeListIntField(payload, prefix, list) {
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

  @spec elm_internal(schema()) :: String.t()
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
    import Dict exposing (Dict)
    import Json.Decode as Decode
    import Json.Encode as Encode


    #{elm_list_helpers()}

    #{elm_dict_helpers()}

    #{elm_record_helpers(schema)}

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
      list_fields = elm_encode_field_appends(schema, msg.fields)
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
    |> Enum.reject(fn {field, _} -> elm_append_encoded_field?(field.wire_type) end)
    |> Enum.map_join("", fn {field, index} ->
      elm_encode_object_field(schema, field, "field#{index}")
    end)
  end

  defp elm_encode_field_appends(schema, fields) do
    fields
    |> Enum.with_index(1)
    |> Enum.filter(fn {field, _} -> elm_append_encoded_field?(field.wire_type) end)
    |> Enum.map_join("", fn {field, index} ->
      "\n                        ++ #{elm_encode_pairs_expr(schema, field.wire_type, "\"#{field.key}\"", "field#{index}", :raw)}"
    end)
  end

  defp elm_append_encoded_field?({:list, _elem}), do: true
  defp elm_append_encoded_field?({:record, _type, _fields}), do: true
  defp elm_append_encoded_field?({:dict, _elem}), do: true
  defp elm_append_encoded_field?({:union, _type, _ctors}), do: true
  defp elm_append_encoded_field?(_wire_type), do: false

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
  defp elm_decoder(%{wire_type: {:union, _type}}), do: "Decode.int"
  defp elm_decoder(%{wire_type: :int}), do: "Decode.int"
  defp elm_decoder(%{wire_type: {:enum, _type}}), do: "Decode.int"

  defp elm_decoder(%{wire_type: wire_type, key: key}),
    do: elm_decode_expr(wire_type, "\"#{key}\"", :raw)

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

  defp elm_dict_helpers do
    """
    decodeListBy : String -> (String -> Decode.Decoder a) -> Decode.Decoder (List a)
    decodeListBy prefix decodeItem =
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
                        decodeListByElements prefix decodeItem count 0 []
                )


    decodeListByElements : String -> (String -> Decode.Decoder a) -> Int -> Int -> List a -> Decode.Decoder (List a)
    decodeListByElements prefix decodeItem remaining index acc =
        if remaining <= 0 then
            Decode.succeed (List.reverse acc)
        else
            decodeItem (prefix ++ "_" ++ String.fromInt index)
                |> Decode.andThen
                    (\\value ->
                        decodeListByElements prefix decodeItem (remaining - 1) (index + 1) (value :: acc)
                    )


    encodeListBy : String -> (String -> a -> List ( String, Encode.Value )) -> List a -> List ( String, Encode.Value )
    encodeListBy prefix encodeItem list =
        let
            items =
                if List.length list > #{@list_max_elements} then
                    List.take #{@list_max_elements} list
                else
                    list
        in
        ( prefix ++ "_count", Encode.int (List.length items + #{@wire_code_base}) )
            :: (items
                    |> List.indexedMap
                        (\\index value ->
                            encodeItem (prefix ++ "_" ++ String.fromInt index) value
                        )
                    |> List.concat
               )


    decodeDictStringBy : String -> (String -> Decode.Decoder a) -> Decode.Decoder (Dict String a)
    decodeDictStringBy prefix decodeValue =
        Decode.field (prefix ++ "_count") Decode.int
            |> Decode.andThen
                (\\wireCount ->
                    let
                        count =
                            wireCount - #{@wire_code_base}
                    in
                    if count < 0 then
                        Decode.fail "Invalid dict count"
                    else
                        decodeDictStringByElements prefix decodeValue count 0 []
                )


    decodeDictStringByElements : String -> (String -> Decode.Decoder a) -> Int -> Int -> List ( String, a ) -> Decode.Decoder (Dict String a)
    decodeDictStringByElements prefix decodeValue remaining index acc =
        if remaining <= 0 then
            Decode.succeed (Dict.fromList (List.reverse acc))
        else
            Decode.map2 Tuple.pair
                (Decode.field (prefix ++ "_key_" ++ String.fromInt index) Decode.string)
                (decodeValue (prefix ++ "_val_" ++ String.fromInt index))
                |> Decode.andThen
                    (\\entry ->
                        decodeDictStringByElements prefix decodeValue (remaining - 1) (index + 1) (entry :: acc)
                    )


    encodeDictStringBy : String -> (String -> a -> List ( String, Encode.Value )) -> Dict String a -> List ( String, Encode.Value )
    encodeDictStringBy prefix encodeValue dict =
        let
            entries =
                Dict.toList dict |> List.take #{@dict_max_entries}
        in
        ( prefix ++ "_count", Encode.int (List.length entries + #{@wire_code_base}) )
            :: (entries
                    |> List.indexedMap
                        (\\index ( key, value ) ->
                            ( prefix ++ "_key_" ++ String.fromInt index, Encode.string key )
                                :: encodeValue (prefix ++ "_val_" ++ String.fromInt index) value
                        )
                    |> List.concat
               )
    """
  end

  defp elm_record_helpers(%{type_aliases: aliases} = schema) do
    aliases
    |> Enum.map_join("\n\n", fn {type, fields} ->
      wire_fields =
        fields
        |> Enum.map(fn field ->
          Map.put(
            field,
            :wire_type,
            WireFlatten.resolve_type(
              field.type,
              schema.enums,
              schema.payload_unions,
              schema.type_aliases
            )
          )
        end)

      """
      decode#{type} : String -> Decode.Decoder #{type}
      decode#{type} prefix =
      #{elm_record_decoder_body(wire_fields, :raw)}


      decode#{type}Offset : String -> Decode.Decoder #{type}
      decode#{type}Offset prefix =
      #{elm_record_decoder_body(wire_fields, :offset)}


      encode#{type} : String -> #{type} -> List ( String, Encode.Value )
      encode#{type} prefix value =
      #{elm_record_encoder_body(schema, wire_fields, :raw)}


      encode#{type}Offset : String -> #{type} -> List ( String, Encode.Value )
      encode#{type}Offset prefix value =
      #{elm_record_encoder_body(schema, wire_fields, :offset)}
      """
    end)
  end

  defp elm_record_decoder_body(fields, offset_mode) do
    names = Enum.map(fields, & &1.name)
    ctor = "{ " <> Enum.map_join(names, ", ", &"#{&1} = #{&1}") <> " }"

    case fields do
      [] ->
        "    Decode.succeed {}"

      [field] ->
        """
          #{elm_decode_expr(field.wire_type, ~s<(prefix ++ "_#{field.name}")>, offset_mode)}
              |> Decode.map (\\#{field.name} -> #{ctor})
        """

      fields ->
        args = Enum.map_join(names, " ", &"(\\#{&1} ->")
        closers = String.duplicate(")", length(names))

        decoders =
          fields
          |> Enum.map_join("\n", fn field ->
            "        (#{elm_decode_expr(field.wire_type, ~s<(prefix ++ "_#{field.name}")>, offset_mode)})"
          end)

        """
          Decode.map#{length(fields)} #{args} #{ctor}#{closers}
        #{decoders}
        """
    end
  end

  defp elm_record_encoder_body(schema, fields, offset_mode) do
    fields
    |> Enum.map_join("\n        ++ ", fn field ->
      elm_encode_pairs_expr(
        schema,
        field.wire_type,
        ~s<(prefix ++ "_#{field.name}")>,
        "value.#{field.name}",
        offset_mode
      )
    end)
    |> case do
      "" -> "    []"
      body -> "    " <> body
    end
  end

  defp elm_decode_expr(:int, prefix, :offset),
    do: "Decode.field #{prefix} Decode.int |> Decode.map (\\wire -> wire - #{@wire_code_base})"

  defp elm_decode_expr(:int, prefix, _mode), do: "Decode.field #{prefix} Decode.int"

  defp elm_decode_expr(:bool, prefix, _mode),
    do:
      "Decode.field #{prefix} (Decode.andThen (\\value -> if value == #{@wire_true_code} then Decode.succeed True else if value == #{@wire_false_code} then Decode.succeed False else Decode.fail \"Invalid bool wire code\") Decode.int)"

  defp elm_decode_expr(:string, prefix, _mode), do: "Decode.field #{prefix} Decode.string"
  defp elm_decode_expr({:enum, _type}, prefix, _mode), do: "Decode.field #{prefix} Decode.int"

  defp elm_decode_expr({:record, type, _fields}, prefix, :offset),
    do: "decode#{type}Offset #{prefix}"

  defp elm_decode_expr({:record, type, _fields}, prefix, _mode), do: "decode#{type} #{prefix}"
  defp elm_decode_expr({:list, :int}, prefix, _mode), do: "decodeListInt #{prefix}"

  defp elm_decode_expr({:list, elem}, prefix, _mode),
    do: "decodeListBy #{prefix} (\\itemPrefix -> #{elm_decode_expr(elem, "itemPrefix", :offset)})"

  defp elm_decode_expr({:dict, elem}, prefix, _mode),
    do:
      "decodeDictStringBy #{prefix} (\\valuePrefix -> #{elm_decode_expr(elem, "valuePrefix", :offset)})"

  defp elm_decode_expr({:union, type, _ctors}, prefix, _mode), do: "decode#{type}Wire #{prefix}"

  defp elm_encode_pairs_expr(_schema, :int, prefix, value, :offset),
    do: "[ ( #{prefix}, Encode.int (#{value} + #{@wire_code_base}) ) ]"

  defp elm_encode_pairs_expr(_schema, :int, prefix, value, _mode),
    do: "[ ( #{prefix}, Encode.int #{value} ) ]"

  defp elm_encode_pairs_expr(_schema, :bool, prefix, value, _mode),
    do:
      "[ ( #{prefix}, Encode.int (if #{value} then #{@wire_true_code} else #{@wire_false_code}) ) ]"

  defp elm_encode_pairs_expr(_schema, :string, prefix, value, _mode),
    do: "[ ( #{prefix}, Encode.string #{value} ) ]"

  defp elm_encode_pairs_expr(schema, {:enum, _type} = wire_type, prefix, value, _mode),
    do:
      "[ ( #{prefix}, Encode.int (#{elm_encode_value(schema, %{wire_type: wire_type}, value)}) ) ]"

  defp elm_encode_pairs_expr(_schema, {:record, type, _fields}, prefix, value, :offset),
    do: "encode#{type}Offset #{prefix} #{value}"

  defp elm_encode_pairs_expr(_schema, {:record, type, _fields}, prefix, value, _mode),
    do: "encode#{type} #{prefix} #{value}"

  defp elm_encode_pairs_expr(_schema, {:list, :int}, prefix, value, _mode),
    do: "encodeListInt #{prefix} #{value}"

  defp elm_encode_pairs_expr(schema, {:list, elem}, prefix, value, _mode),
    do:
      "encodeListBy #{prefix} (\\itemPrefix itemValue -> #{elm_encode_pairs_expr(schema, elem, "itemPrefix", "itemValue", :offset)}) #{value}"

  defp elm_encode_pairs_expr(schema, {:dict, elem}, prefix, value, _mode),
    do:
      "encodeDictStringBy #{prefix} (\\valuePrefix dictValue -> #{elm_encode_pairs_expr(schema, elem, "valuePrefix", "dictValue", :offset)}) #{value}"

  defp elm_encode_pairs_expr(_schema, {:union, type, _ctors}, prefix, value, _mode),
    do: "encode#{type}Wire #{prefix} #{value}"

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

  defp elm_payload_union_helpers(%{payload_unions: payload_unions} = schema) do
    payload_unions
    |> Enum.map_join("\n\n", fn {type, ctors} ->
      legacy = WireFlatten.legacy_union?(schema, type)

      legacy_helpers =
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

      if legacy do
        legacy_helpers
      else
        legacy_helpers <> "\n\n" <> elm_generic_union_helpers(schema, type, ctors)
      end
    end)
  end

  defp elm_generic_union_helpers(schema, type, ctors) do
    """
    decode#{type}Wire : String -> Decode.Decoder #{type}
    decode#{type}Wire prefix =
        Decode.field (prefix ++ "_tag") Decode.int
            |> Decode.andThen
                (\\tag ->
                    case tag of
    #{elm_generic_union_decode_branches(schema, type, ctors)}
                        _ ->
                            Decode.fail ("Unknown #{type} tag: " ++ String.fromInt tag)
                )


    encode#{type}Wire : String -> #{type} -> List ( String, Encode.Value )
    encode#{type}Wire prefix value =
        case value of
    #{elm_generic_union_encode_branches(schema, ctors)}
    """
  end

  defp elm_generic_union_decode_branches(schema, _type, ctors) do
    ctors
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {ctor, tag} ->
      case ctor.args do
        [] ->
          "                    #{tag} ->\n                        Decode.succeed #{ctor.name}"

        args ->
          decoders =
            args
            |> Enum.with_index(1)
            |> Enum.map(fn {arg_type, index} ->
              wire_type =
                WireFlatten.resolve_type(
                  arg_type,
                  schema.enums,
                  schema.payload_unions,
                  schema.type_aliases
                )

              prefix = ~s<(prefix ++ "_#{Macro.underscore(ctor.name)}_arg#{index}")>
              elm_decode_expr(wire_type, prefix, :raw)
            end)

          constructor = "#{ctor.name}#{Enum.map_join(1..length(args), "", &" arg#{&1}")}"
          mapper = "\\#{Enum.map_join(1..length(args), " ", &"arg#{&1}")} -> #{constructor}"

          """
                              #{tag} ->
                                  #{elm_map_decoder(decoders, mapper)}
          """
      end
    end)
  end

  defp elm_generic_union_encode_branches(schema, ctors) do
    ctors
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {ctor, tag} ->
      args =
        if ctor.args == [] do
          ""
        else
          Enum.map_join(1..length(ctor.args), "", &" arg#{&1}")
        end

      pairs =
        ctor.args
        |> Enum.with_index(1)
        |> Enum.map_join("\n                ++ ", fn {arg_type, index} ->
          wire_type =
            WireFlatten.resolve_type(
              arg_type,
              schema.enums,
              schema.payload_unions,
              schema.type_aliases
            )

          prefix = ~s<(prefix ++ "_#{Macro.underscore(ctor.name)}_arg#{index}")>
          elm_encode_pairs_expr(schema, wire_type, prefix, "arg#{index}", :raw)
        end)

      pairs = if pairs == "", do: "[]", else: pairs

      """
              #{ctor.name}#{args} ->
                  ( prefix ++ "_tag", Encode.int #{tag} )
                      :: (#{pairs})
      """
    end)
  end

  defp elm_map_decoder([single], mapper), do: "Decode.map (#{mapper}) (#{single})"

  defp elm_map_decoder(decoders, mapper) do
    """
    Decode.map#{length(decoders)} (#{mapper})
    #{Enum.map_join(decoders, "\n", &"                            (#{&1})")}
    """
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

  defp c_required_field_expr(%{wire_type: wire_type}, index) do
    if c_composite_wire_type?(wire_type), do: "true", else: "decoder->saw_fields[#{index}]"
  end

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

  defp c_missing_field_default(%{wire_type: wire_type, key: key}, _index)
       when tuple_size(wire_type) in [2, 3] do
    if c_composite_wire_type?(wire_type) do
      WireFlatten.slots_for_field(
        %{key: key, name: key, type: key, wire_type: wire_type},
        %{
        enums: %{},
        payload_unions: %{},
        type_aliases: %{},
        watch_to_phone: [],
        phone_to_watch: []
      })
      |> Enum.map_join("\n", &c_missing_wire_slot_default/1)
    else
      ""
    end
  end

  defp c_missing_field_default(_field, _index), do: ""

  defp c_missing_wire_slot_default(%{storage_type: :string, c_name: c_name}) do
    """
          if (!decoder->saw_#{c_name}) {
            decoder->message.wire.#{c_name}[0] = '\\0';
          }
    """
  end

  defp c_missing_wire_slot_default(%{storage_type: :bool, c_name: c_name}) do
    """
          if (!decoder->saw_#{c_name}) {
            decoder->message.wire.#{c_name} = false;
          }
    """
  end

  defp c_missing_wire_slot_default(%{c_name: c_name}) do
    """
          if (!decoder->saw_#{c_name}) {
            decoder->message.wire.#{c_name} = 0;
          }
    """
  end

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

  defp c_decode_wire_slot_cases(schema) do
    schema.wire_slots
    |> Enum.uniq_by(& &1.key)
    |> Enum.map_join("\n", fn slot ->
      key_macro = "COMPANION_PROTOCOL_KEY_#{macro_name(slot.key)}"

      """
        if (tuple->key == #{key_macro}) {
          decoder->saw_#{slot.c_name} = true;
      #{c_decode_wire_slot_value(slot)}
          return;
        }
      """
    end)
  end

  defp c_decode_wire_slot_value(%{storage_type: :string, c_name: c_name}) do
    """
      if (tuple->type == TUPLE_CSTRING) {
        strncpy(decoder->message.wire.#{c_name}, tuple->value->cstring, 63);
        decoder->message.wire.#{c_name}[63] = '\\0';
      }
    """
  end

  defp c_decode_wire_slot_value(%{storage_type: :bool, c_name: c_name}) do
    """
      if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
        decoder->message.wire.#{c_name} = tuple->value->int32 == #{@wire_true_code};
      }
    """
  end

  defp c_decode_wire_slot_value(%{wire_offset: :offset, c_name: c_name}) do
    """
      if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
        decoder->message.wire.#{c_name} = tuple->value->int32 - #{@wire_code_base};
        if (decoder->message.wire.#{c_name} < 0) decoder->message.wire.#{c_name} = 0;
      }
    """
  end

  defp c_decode_wire_slot_value(%{c_name: c_name}) do
    """
      if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
        decoder->message.wire.#{c_name} = tuple->value->int32;
      }
    """
  end

  defp c_payload_expr(%{fields: []}), do: "      ElmcValue *payload = elmc_new_int_take(0);"

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

    """
    #{vars}
          ElmcValue *payload = #{tuple};
    """
  end

  defp c_value_expr(%{wire_type: :string}, index),
    do: "elmc_new_string_take(message->string_fields[#{index}])"

  defp c_value_expr(%{wire_type: :bool}, index),
    do: "elmc_new_bool_take(message->bool_fields[#{index}] ? 1 : 0)"

  defp c_value_expr(%{wire_type: {:enum, type}}, index),
    do: "elmc_new_int_take(#{c_runtime_tag_function(type)}(message->int_fields[#{index}]))"

  defp c_value_expr(%{wire_type: {:union, type}}, index),
    do:
      "companion_protocol_new_union_value(#{c_runtime_tag_function(type)}(message->int_fields[#{index}]), message->union_value_fields[#{index}])"

  defp c_value_expr(%{wire_type: {:union, _type, _ctors}, key: key}, _index),
    do: "#{c_build_function_name(key)}(message)"

  defp c_value_expr(%{wire_type: {:list, :int}}, index),
    do: "elmc_list_from_int_array_take(message->list_values[#{index}], message->list_counts[#{index}])"

  defp c_value_expr(%{wire_type: {:record, _type, _fields}, key: key}, _index),
    do: "#{c_build_function_name(key)}(message)"

  defp c_value_expr(%{wire_type: {:list, _elem}, key: key}, _index),
    do: "#{c_build_function_name(key)}(message)"

  defp c_value_expr(%{wire_type: {:dict, _elem}, key: key}, _index),
    do: "#{c_build_function_name(key)}(message)"

  defp c_value_expr(_field, index), do: "elmc_new_int_take(message->int_fields[#{index}])"

  defp c_composite_build_helpers(schema) do
    schema.phone_to_watch
    |> Enum.flat_map(& &1.fields)
    |> Enum.filter(&c_composite_wire_type?(&1.wire_type))
    |> Enum.uniq_by(& &1.key)
    |> Enum.map_join("\n\n", fn field ->
      {body, result} = c_build_value_from_wire(field.wire_type, field.key, schema, "v")

      """
      static ElmcValue *#{c_build_function_name(field.key)}(const CompanionProtocolPhoneToWatchMessage *message) {
      #{body}
        return #{result};
      }
      """
    end)
  end

  @spec c_composite_wire_type?(WireSchema.wire_type()) :: boolean()
  defp c_composite_wire_type?({:record, _type, _fields}), do: true
  defp c_composite_wire_type?({:list, elem}), do: elem != :int
  defp c_composite_wire_type?({:dict, _elem}), do: true
  defp c_composite_wire_type?({:union, _type, _ctors}), do: true
  defp c_composite_wire_type?(_wire_type), do: false

  defp c_build_function_name(key),
    do: "companion_protocol_build_#{macro_name(key) |> String.downcase()}"

  defp c_build_value_from_wire(:int, key, _schema, _var_prefix) do
    slot =
      WireFlatten.slots_for_field(%{key: key, name: key, type: key, wire_type: :int}, empty_wire_schema())
      |> hd()

    {"", "elmc_new_int_take(message->wire.#{slot.c_name})"}
  end

  defp c_build_value_from_wire(:bool, key, _schema, _var_prefix) do
    slot =
      WireFlatten.slots_for_field(%{key: key, name: key, type: key, wire_type: :bool}, empty_wire_schema())
      |> hd()

    {"", "elmc_new_bool_take(message->wire.#{slot.c_name} ? 1 : 0)"}
  end

  defp c_build_value_from_wire(:string, key, _schema, _var_prefix) do
    slot =
      WireFlatten.slots_for_field(%{key: key, name: key, type: key, wire_type: :string}, empty_wire_schema())
      |> hd()

    {"", "elmc_new_string_take(message->wire.#{slot.c_name})"}
  end

  defp c_build_value_from_wire({:enum, type}, key, _schema, _var_prefix) do
    slot =
      WireFlatten.slots_for_field(
        %{key: key, name: key, type: type, wire_type: {:enum, type}},
        empty_wire_schema()
      )
      |> hd()

    {"", "elmc_new_int_take(#{c_runtime_tag_function(type)}(message->wire.#{slot.c_name}))"}
  end

  defp c_build_value_from_wire({:record, _type, fields}, key, schema, var_prefix) do
    built =
      fields
      |> Enum.with_index()
      |> Enum.map(fn {field, index} ->
        child_key = "#{key}_#{field.name}"
        child_var = "#{var_prefix}_field_#{index}"

        {child_body, child_expr} =
          c_build_value_from_wire(field.wire_type, child_key, schema, child_var)

        {field, index, child_var, child_body, child_expr}
      end)

    names =
      fields
      |> Enum.map_join(", ", &~s("#{&1.name}"))

    body =
      built
      |> Enum.map_join("\n", fn {_field, _index, child_var, child_body, child_expr} ->
        """
        #{child_body}
        ElmcValue *#{child_var} = #{child_expr};
        if (!#{child_var}) return NULL;
        """
      end)

    values =
      built |> Enum.map_join(", ", fn {_field, _index, child_var, _body, _expr} -> child_var end)

    body =
      body <>
        """
        const char *#{var_prefix}_names[] = { #{names} };
        ElmcValue *#{var_prefix}_values[] = { #{values} };
        """

    {body, "elmc_record_new_take(#{length(fields)}, #{var_prefix}_names, #{var_prefix}_values)"}
  end

  defp c_build_value_from_wire({:list, elem_type}, key, schema, var_prefix) do
    count_slot =
      WireFlatten.slots_for_field(%{key: key, name: key, type: key, wire_type: {:list, elem_type}}, schema)
      |> Enum.find(&String.ends_with?(&1.key, "_count"))

    element_builds =
      0..(@list_max_elements - 1)
      |> Enum.map(fn index ->
        child_key = "#{key}_#{index}"
        child_var = "#{var_prefix}_item_#{index}"

        {child_body, child_expr} =
          c_build_value_from_wire(elem_type, child_key, schema, child_var)

        """
        if (#{var_prefix}_count > #{index}) {
        #{child_body}
          #{var_prefix}_items[#{index}] = #{child_expr};
          if (!#{var_prefix}_items[#{index}]) return NULL;
        }
        """
      end)
      |> Enum.join("\n")

    body = """
        int32_t #{var_prefix}_count = message->wire.#{count_slot.c_name};
        if (#{var_prefix}_count < 0) #{var_prefix}_count = 0;
        if (#{var_prefix}_count > #{@list_max_elements}) #{var_prefix}_count = #{@list_max_elements};
        ElmcValue *#{var_prefix}_items[#{@list_max_elements}];
      #{element_builds}
    """

    {body, "elmc_list_from_values_take(#{var_prefix}_items, #{var_prefix}_count)"}
  end

  defp c_build_value_from_wire({:dict, value_type}, key, schema, var_prefix) do
    count_slot =
      WireFlatten.slots_for_field(%{key: key, name: key, type: key, wire_type: {:dict, value_type}}, schema)
      |> Enum.find(&String.ends_with?(&1.key, "_count"))

    entry_builds =
      0..(@dict_max_entries - 1)
      |> Enum.map(fn index ->
        key_slot =
          WireFlatten.slots_for_field(
            %{key: "#{key}_key_#{index}", name: key, type: key, wire_type: :string},
            schema
          )
          |> hd()

        value_key = "#{key}_val_#{index}"
        value_var = "#{var_prefix}_value_#{index}"

        {value_body, value_expr} =
          c_build_value_from_wire(value_type, value_key, schema, value_var)

        """
        if (#{var_prefix}_count > #{index}) {
          ElmcValue *#{var_prefix}_key_#{index} = elmc_new_string_take(message->wire.#{key_slot.c_name});
        #{value_body}
          ElmcValue *#{value_var} = #{value_expr};
          if (!#{var_prefix}_key_#{index} || !#{value_var}) return NULL;
          #{var_prefix}_pairs[#{index}] = elmc_tuple2_take_value(#{var_prefix}_key_#{index}, #{value_var});
          if (!#{var_prefix}_pairs[#{index}]) return NULL;
        }
        """
      end)
      |> Enum.join("\n")

    body = """
        int32_t #{var_prefix}_count = message->wire.#{count_slot.c_name};
        if (#{var_prefix}_count < 0) #{var_prefix}_count = 0;
        if (#{var_prefix}_count > #{@dict_max_entries}) #{var_prefix}_count = #{@dict_max_entries};
        ElmcValue *#{var_prefix}_pairs[#{@dict_max_entries}];
      #{entry_builds}
        ElmcValue *#{var_prefix}_pair_list = elmc_list_from_values_take(#{var_prefix}_pairs, #{var_prefix}_count);
        if (!#{var_prefix}_pair_list) return NULL;
        ElmcValue *#{var_prefix}_dict = elmc_dict_from_list_take(#{var_prefix}_pair_list);
        elmc_release(#{var_prefix}_pair_list);
    """

    {body, "#{var_prefix}_dict"}
  end

  defp c_build_value_from_wire({:union, type, ctors}, key, schema, var_prefix) do
    tag_slot =
      WireFlatten.slots_for_field(
        %{key: key, name: key, type: type, wire_type: {:union, type, ctors}},
        schema
      )
      |> Enum.find(&String.ends_with?(&1.key, "_tag"))

    cases =
      ctors
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {ctor, tag_code} ->
        {payload_body, payload_expr} =
          c_union_payload_build(ctor, key, schema, "#{var_prefix}_#{Macro.underscore(ctor.name)}")

        """
          case #{tag_code}: {
        #{payload_body}
            ElmcValue *#{var_prefix}_tag = elmc_new_int_take(#{c_runtime_tag_function(type)}(#{tag_code}));
            ElmcValue *#{var_prefix}_payload = #{payload_expr};
            if (!#{var_prefix}_tag || !#{var_prefix}_payload) return NULL;
            return elmc_tuple2_take_value(#{var_prefix}_tag, #{var_prefix}_payload);
          }
        """
      end)

    body = """
        switch (message->wire.#{tag_slot.c_name} + #{@wire_code_base}) {
      #{cases}
          default:
            return NULL;
        }
    """

    {body, "NULL"}
  end

  defp c_union_payload_build(%{args: []}, _key, _schema, _var_prefix), do: {"", "elmc_new_int_take(0)"}

  defp c_union_payload_build(%{name: ctor_name, args: [arg_type]}, key, schema, var_prefix) do
    wire_type =
      WireFlatten.resolve_type(arg_type, schema.enums, schema.payload_unions, schema.type_aliases)

    child_key = "#{key}_#{Macro.underscore(ctor_name)}_arg1"
    c_build_value_from_wire(wire_type, child_key, schema, var_prefix <> "_arg1")
  end

  defp c_union_payload_build(%{name: ctor_name, args: args}, key, schema, var_prefix) do
    built =
      args
      |> Enum.with_index(1)
      |> Enum.map(fn {arg_type, arg_index} ->
        wire_type =
          WireFlatten.resolve_type(
            arg_type,
            schema.enums,
            schema.payload_unions,
            schema.type_aliases
          )

        child_key = "#{key}_#{Macro.underscore(ctor_name)}_arg#{arg_index}"
        child_var = "#{var_prefix}_arg#{arg_index}"
        {body, expr} = c_build_value_from_wire(wire_type, child_key, schema, child_var)
        {child_var, body, expr}
      end)

    body =
      built
      |> Enum.map_join("\n", fn {child_var, child_body, child_expr} ->
        """
        #{child_body}
            ElmcValue *#{child_var} = #{child_expr};
            if (!#{child_var}) return NULL;
        """
      end)

    tuple =
      built
      |> Enum.map(fn {child_var, _body, _expr} -> child_var end)
      |> c_tuple_chain()

    releases =
      built
      |> Enum.map_join("\n", fn {child_var, _body, _expr} ->
        "          elmc_release(#{child_var});"
      end)

    body =
      body <>
        """
            ElmcValue *#{var_prefix}_payload = #{tuple};
        #{releases}
        """

    {body, "#{var_prefix}_payload"}
  end

  defp empty_wire_schema do
    %{enums: %{}, payload_unions: %{}, type_aliases: %{}, watch_to_phone: [], phone_to_watch: []}
  end

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
      |> Enum.flat_map(&c_runtime_tag_wire_types(&1.wire_type))
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

  defp c_runtime_tag_wire_types({:enum, type}), do: [{:enum, type}]
  defp c_runtime_tag_wire_types({:union, type}), do: [{:union, type}]

  defp c_runtime_tag_wire_types({:union, type, ctors}) do
    nested =
      ctors
      |> Enum.flat_map(& &1.args)
      |> Enum.flat_map(&c_runtime_tag_wire_types(WireFlatten.resolve_type(&1, %{}, %{}, %{})))

    [{:union, type} | nested]
  end

  defp c_runtime_tag_wire_types({:list, elem}), do: c_runtime_tag_wire_types(elem)
  defp c_runtime_tag_wire_types({:dict, elem}), do: c_runtime_tag_wire_types(elem)

  defp c_runtime_tag_wire_types({:record, _type, fields}) do
    Enum.flat_map(fields, &c_runtime_tag_wire_types(&1.wire_type))
  end

  defp c_runtime_tag_wire_types(_wire_type), do: []

  defp c_runtime_tag_function(type),
    do: "companion_protocol_runtime_tag_#{macro_name(type)}"

  defp c_tuple_chain([single]), do: single
  defp c_tuple_chain([head | rest]), do: "elmc_tuple2_take_value(#{head}, #{c_tuple_chain(rest)})"

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

  defp js_field_prop(%{wire_type: wire_type, key: key, name: name}, _index)
       when tuple_size(wire_type) in [2, 3] do
    if c_composite_wire_type?(wire_type) do
      "    #{name}: #{js_decode_expr(wire_type, key)}"
    else
      "    #{name}: payload[#{js_payload_key(key)}]"
    end
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
    "      encodeListIntField(payload, #{js_string_key_macro(key)}, #{source});"
  end

  defp js_encode_field_writes(%{wire_type: wire_type, key: key}, source)
       when tuple_size(wire_type) in [2, 3] do
    if c_composite_wire_type?(wire_type) do
      js_encode_writes(wire_type, key, source, "      ")
    else
      "      payload[#{js_payload_key(key)}] = #{js_encode_field_value(%{wire_type: wire_type}, source)};"
    end
  end

  defp js_encode_field_writes(field, source) do
    "      payload[#{js_payload_key(field.key)}] = #{js_encode_field_value(field, source)};"
  end

  defp js_string_key_macro(key), do: "\"#{key}\""

  defp js_encode_field_value(%{wire_type: :bool}, source),
    do: "(#{source} ? #{@wire_true_code} : #{@wire_false_code})"

  defp js_encode_field_value(_field, source), do: source

  defp js_decode_expr(:int, key), do: "(payload[#{js_payload_key(key)}] || 0)"
  defp js_decode_expr(:bool, key), do: "(payload[#{js_payload_key(key)}] === #{@wire_true_code})"
  defp js_decode_expr(:string, key), do: "(payload[#{js_payload_key(key)}] || \"\")"

  defp js_decode_expr({:enum, _type}, key),
    do: "(payload[#{js_payload_key(key)}] || #{@wire_code_base})"

  defp js_decode_expr({:record, _type, fields}, key) do
    props =
      fields
      |> Enum.map_join(", ", fn field ->
        "#{field.name}: #{js_decode_expr(field.wire_type, "#{key}_#{field.name}")}"
      end)

    "({ #{props} })"
  end

  defp js_decode_expr({:list, elem_type}, key) do
    elem_reads =
      0..(@list_max_elements - 1)
      |> Enum.map_join("\n", fn index ->
        "        if (i === #{index}) return #{js_decode_expr(elem_type, "#{key}_#{index}")};"
      end)

    """
    (function () {
          var countWire = payload[#{js_payload_key(key <> "_count")}];
          var count = typeof countWire === "number" ? Math.max(0, countWire - #{@wire_code_base}) : 0;
          if (count > #{@list_max_elements}) count = #{@list_max_elements};
          var out = [];
          for (var i = 0; i < count; i++) {
    #{elem_reads}
          }
          return out;
        })()
    """
    |> String.trim()
  end

  defp js_decode_expr({:dict, value_type}, key) do
    entry_reads =
      0..(@dict_max_entries - 1)
      |> Enum.map_join("\n", fn index ->
        """
            if (i === #{index}) {
              var dictKey = payload[#{js_payload_key("#{key}_key_#{index}")}] || "";
              out[dictKey] = #{js_decode_expr(value_type, "#{key}_val_#{index}")};
            }
        """
      end)

    """
    (function () {
          var countWire = payload[#{js_payload_key(key <> "_count")}];
          var count = typeof countWire === "number" ? Math.max(0, countWire - #{@wire_code_base}) : 0;
          if (count > #{@dict_max_entries}) count = #{@dict_max_entries};
          var out = {};
          for (var i = 0; i < count; i++) {
    #{entry_reads}
          }
          return out;
        })()
    """
    |> String.trim()
  end

  defp js_encode_writes(:int, key, source, indent),
    do: "#{indent}payload[#{js_payload_key(key)}] = #{source};"

  defp js_encode_writes(:bool, key, source, indent),
    do:
      "#{indent}payload[#{js_payload_key(key)}] = (#{source} ? #{@wire_true_code} : #{@wire_false_code});"

  defp js_encode_writes(:string, key, source, indent),
    do: "#{indent}payload[#{js_payload_key(key)}] = #{source} || \"\";"

  defp js_encode_writes({:enum, _type}, key, source, indent),
    do: "#{indent}payload[#{js_payload_key(key)}] = #{source};"

  defp js_encode_writes({:record, _type, fields}, key, source, indent) do
    fields
    |> Enum.map_join("\n", fn field ->
      js_encode_writes(
        field.wire_type,
        "#{key}_#{field.name}",
        "#{source} && #{source}.#{field.name}",
        indent
      )
    end)
  end

  defp js_encode_writes({:list, elem_type}, key, source, indent) do
    items_var = js_temp_name(key, "items")

    element_blocks =
      0..(@list_max_elements - 1)
      |> Enum.map_join("\n", fn index ->
        """
        #{indent}  if (#{items_var}.length > #{index}) {
        #{js_encode_writes_offset(elem_type, "#{key}_#{index}", "#{items_var}[#{index}]", indent <> "    ")}
        #{indent}  }
        """
      end)

    """
    #{indent}(function () {
    #{indent}  var #{items_var} = Array.isArray(#{source}) ? #{source}.slice(0, #{@list_max_elements}) : [];
    #{indent}  payload[#{js_payload_key(key <> "_count")}] = #{items_var}.length + #{@wire_code_base};
    #{element_blocks}
    #{indent}})();
    """
  end

  defp js_encode_writes({:dict, value_type}, key, source, indent) do
    entries_var = js_temp_name(key, "entries")

    entry_blocks =
      0..(@dict_max_entries - 1)
      |> Enum.map_join("\n", fn index ->
        """
        #{indent}  if (#{entries_var}.length > #{index}) {
        #{indent}    payload[#{js_payload_key("#{key}_key_#{index}")}] = #{entries_var}[#{index}][0];
        #{js_encode_writes_offset(value_type, "#{key}_val_#{index}", "#{entries_var}[#{index}][1]", indent <> "    ")}
        #{indent}  }
        """
      end)

    """
    #{indent}(function () {
    #{indent}  var #{entries_var} = Object.entries(#{source} || {}).slice(0, #{@dict_max_entries});
    #{indent}  payload[#{js_payload_key(key <> "_count")}] = #{entries_var}.length + #{@wire_code_base};
    #{entry_blocks}
    #{indent}})();
    """
  end

  defp js_encode_writes({:union, _type, ctors}, key, source, indent) do
    tag_writes =
      ctors
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {ctor, tag} ->
        args =
          ctor.args
          |> Enum.with_index(1)
          |> Enum.map_join("\n", fn {arg_type, index} ->
            wire_type = WireFlatten.resolve_type(arg_type, %{}, %{}, %{})

            js_encode_writes(
              wire_type,
              "#{key}_#{Macro.underscore(ctor.name)}_arg#{index}",
              "#{source}.args && #{source}.args[#{index - 1}]",
              indent <> "    "
            )
          end)

        """
        #{indent}  if (#{source} && #{source}.tag === #{tag}) {
        #{indent}    payload[#{js_payload_key(key <> "_tag")}] = #{tag};
        #{args}
        #{indent}    return;
        #{indent}  }
        """
      end)

    """
    #{indent}(function () {
    #{tag_writes}
    #{indent}})();
    """
  end

  defp js_temp_name(key, suffix) do
    key
    |> macro_name()
    |> String.downcase()
    |> then(&"#{&1}_#{suffix}")
  end

  defp js_encode_writes_offset(:int, key, source, indent),
    do: "#{indent}payload[#{js_payload_key(key)}] = (#{source} || 0) + #{@wire_code_base};"

  defp js_encode_writes_offset({:record, _type, fields}, key, source, indent) do
    fields
    |> Enum.map_join("\n", fn field ->
      js_encode_writes_offset(
        field.wire_type,
        "#{key}_#{field.name}",
        "#{source} && #{source}.#{field.name}",
        indent
      )
    end)
  end

  defp js_encode_writes_offset(wire_type, key, source, indent),
    do: js_encode_writes(wire_type, key, source, indent)

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
