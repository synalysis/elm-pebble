defmodule Ide.CompanionProtocolGenerator do
  @moduledoc false

  @type schema :: %{
          enums: %{optional(String.t()) => [String.t()]},
          payload_unions: %{optional(String.t()) => [constructor()]},
          watch_to_phone: [message()],
          phone_to_watch: [message()],
          key_ids: %{optional(String.t()) => pos_integer()}
        }
  @type constructor :: %{
          name: String.t(),
          args: [String.t()]
        }
  @type message :: %{
          name: String.t(),
          tag: pos_integer(),
          fields: [field()]
        }
  @type field :: %{
          name: String.t(),
          key: String.t(),
          type: String.t(),
          wire_type: :int | :bool | :string | {:enum, String.t()} | {:union, String.t()}
        }

  @spec generate(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
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

  @spec generate_elm_internal(String.t(), String.t()) :: :ok | {:error, term()}
  def generate_elm_internal(types_elm, out_elm) do
    with {:ok, source} <- File.read(types_elm),
         {:ok, schema} <- schema_from_source(source),
         :ok <- File.mkdir_p(Path.dirname(out_elm)),
         :ok <- File.write(out_elm, elm_internal(schema)) do
      :ok
    end
  end

  @spec message_keys(String.t()) ::
          {:ok, %{optional(String.t()) => pos_integer()}} | {:error, term()}
  def message_keys(types_elm) do
    with {:ok, source} <- File.read(types_elm),
         {:ok, schema} <- schema_from_source(source) do
      {:ok, schema.key_ids}
    end
  end

  @spec schema_from_source(String.t()) :: {:ok, schema()} | {:error, term()}
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
        |> Enum.map(fn line ->
          [ctor | args] = String.split(line, ~r/\s+/, trim: true)
          %{name: ctor, args: args}
        end)

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

  defp wire_type("Int", _enums, _payload_unions), do: :int
  defp wire_type("Bool", _enums, _payload_unions), do: :bool
  defp wire_type("String", _enums, _payload_unions), do: :string

  defp wire_type(type, enums, payload_unions) do
    cond do
      Map.has_key?(enums, type) -> {:enum, type}
      Map.has_key?(payload_unions, type) -> {:union, type}
      true -> :int
    end
  end

  defp field_keys(%{wire_type: {:union, _type}, key: key}), do: [key <> "_tag", key <> "_value"]
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
        |> Enum.map(fn {ctor, id} ->
          "#define COMPANION_PROTOCOL_ENUM_#{macro_name(type)}_#{macro_name(ctor)} #{id}"
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

    typedef enum {
      COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_UNKNOWN = 0,
    #{kind_lines}
    } CompanionProtocolPhoneToWatchKind;

    typedef struct {
      CompanionProtocolPhoneToWatchKind kind;
      int32_t int_fields[COMPANION_PROTOCOL_MAX_FIELDS];
      int32_t union_value_fields[COMPANION_PROTOCOL_MAX_FIELDS];
      bool bool_fields[COMPANION_PROTOCOL_MAX_FIELDS];
      char string_fields[COMPANION_PROTOCOL_MAX_FIELDS][64];
    } CompanionProtocolPhoneToWatchMessage;

    typedef struct {
      bool saw_tag;
      int32_t tag;
      CompanionProtocolPhoneToWatchMessage message;
      bool saw_fields[COMPANION_PROTOCOL_MAX_FIELDS];
      bool saw_union_value_fields[COMPANION_PROTOCOL_MAX_FIELDS];
    } CompanionProtocolPhoneToWatchDecoder;

    bool companion_protocol_encode_watch_to_phone(DictionaryIterator *iter, int32_t tag, int32_t value);
    void companion_protocol_phone_to_watch_decoder_init(CompanionProtocolPhoneToWatchDecoder *decoder);
    void companion_protocol_phone_to_watch_decoder_push_tuple(
        CompanionProtocolPhoneToWatchDecoder *decoder, const Tuple *tuple);
    bool companion_protocol_phone_to_watch_decoder_finish(
        const CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out);
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
        required =
          msg.fields
          |> Enum.with_index()
          |> Enum.map_join(" && ", fn {field, index} -> c_required_field_expr(field, index) end)

        required = if required == "", do: "true", else: required

        """
            case COMPANION_PROTOCOL_TAG_#{macro_name(msg.name)}:
              if (!(#{required})) return false;
              out->kind = COMPANION_PROTOCOL_PHONE_TO_WATCH_KIND_#{macro_name(msg.name)};
              return true;
        """
      end)

    dispatch_cases =
      schema.phone_to_watch
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {msg, phone_to_watch_tag} ->
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
      end)

    """
    #include "companion_protocol.h"
    #include <string.h>

    #{c_runtime_tag_helpers(schema, runtime_tags)}

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

    static ElmcValue *companion_protocol_new_phone_to_watch_message(int32_t tag, ElmcValue *payload) {
      if (!payload) return NULL;
      ElmcValue *tag_value = elmc_new_int(tag);
      if (!tag_value) return NULL;

      ElmcValue *out = elmc_tuple2(tag_value, payload);
      elmc_release(tag_value);
      return out;
    }

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
      memset(decoder->saw_union_value_fields, 0, sizeof(decoder->saw_union_value_fields));
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
        const CompanionProtocolPhoneToWatchDecoder *decoder, CompanionProtocolPhoneToWatchMessage *out) {
      if (!decoder || !out || !decoder->saw_tag) return false;
      *out = decoder->message;

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
          |> Enum.map_join("\n", fn {ctor, id} -> "  #{id}: \"#{ctor}\"," end)

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
              payload[constants.KEY_MESSAGE_TAG] = #{msg.tag};
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

    function decodeWatchToPhonePayload(payload) {
      if (!payload) {
        return null;
      }

      var tag = payload[constants.KEY_MESSAGE_TAG];
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
          "                #{msg.tag} ->\n                    Ok #{msg.name}\n"

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
      fields = elm_encode_object_fields(schema, msg)

      """
              #{msg.name}#{args} ->
                  Encode.object
                      [ ( "message_tag", Encode.int #{msg.tag} )#{fields}
                      ]
      """
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

  defp elm_encode_object_fields(schema, %{fields: fields}) do
    fields
    |> Enum.with_index(1)
    |> Enum.map_join("", fn {field, index} ->
      elm_encode_object_field(schema, field, "field#{index}")
    end)
  end

  defp elm_encode_object_field(_schema, %{wire_type: {:union, type}, key: key}, value) do
    "\n                , ( \"#{key}_tag\", Encode.int (#{elm_union_tag_encode_name(type)} #{value}) )" <>
      "\n                , ( \"#{key}_value\", Encode.int (#{elm_union_value_encode_name(type)} #{value}) )"
  end

  defp elm_encode_object_field(schema, field, value) do
    "\n                , ( \"#{field.key}\", #{elm_encoder(schema, field, value)} )"
  end

  defp elm_decoder(%{wire_type: :bool}), do: "(Decode.map ((/=) 0) Decode.int)"
  defp elm_decoder(%{wire_type: :string}), do: "Decode.string"
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
    do: "if #{value} then 1 else 0"

  defp elm_encode_value(_schema, %{wire_type: {:enum, _type}, type: type}, value),
    do: "#{elm_enum_encode_name(type)} #{value}"

  defp elm_encode_value(_schema, %{wire_type: {:union, type}}, value),
    do: "#{elm_union_tag_encode_name(type)} #{value}"

  defp elm_encode_value(_schema, _field, value), do: value

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
      "        #{ctor.name}#{elm_union_pattern_args(ctor.args)} ->\n            #{index}"
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
        "        #{index} ->\n            #{elm_union_decode_expr(ctor)}"
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
      "        #{ctor} ->\n            #{index}"
    end)
  end

  defp elm_enum_from_code_branches(schema, type) do
    known =
      schema.enums
      |> Map.fetch!(type)
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn {ctor, index} ->
        "        #{index} ->\n            Just #{ctor}"
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

  defp c_required_field_expr(_field, index), do: "decoder->saw_fields[#{index}]"

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
      if (tuple->type == TUPLE_CSTRING && tuple->value->cstring) {
        strncpy(decoder->message.string_fields[#{index}], tuple->value->cstring, 63);
        decoder->message.string_fields[#{index}][63] = '\\0';
      }
    """
  end

  defp c_decode_tuple_field(%{wire_type: :bool}, index) do
    """
      if (tuple->type == TUPLE_INT || tuple->type == TUPLE_UINT) {
        decoder->message.bool_fields[#{index}] = tuple->value->int32 != 0;
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

  defp c_value_expr(_field, index), do: "elmc_new_int(message->int_fields[#{index}])"

  defp c_runtime_tag_helpers(schema, runtime_tags) do
    schema
    |> c_runtime_tag_types()
    |> Enum.map_join("\n\n", fn {type, ctors} ->
      cases =
        ctors
        |> Enum.with_index()
        |> Enum.map_join("\n", fn {ctor, code} ->
          runtime_tag =
            runtime_tags
            |> Map.get(type, %{})
            |> Map.get(ctor, code + 1)

          "    case #{code}: return #{runtime_tag};"
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
    enum_types = schema.enums

    payload_union_types =
      schema.payload_unions
      |> Map.new(fn {type, ctors} -> {type, Enum.map(ctors, & &1.name)} end)

    Map.merge(enum_types, payload_union_types)
  end

  defp c_runtime_tag_function(type),
    do: "companion_protocol_runtime_tag_#{macro_name(type)}"

  defp c_tuple_chain([single]), do: single
  defp c_tuple_chain([head | rest]), do: "elmc_tuple2(#{head}, #{c_tuple_chain(rest)})"

  defp js_field_prop(%{wire_type: {:enum, type}, key: key, name: name}, _index) do
    code = "payload[constants.KEY_#{macro_name(key)}]"

    "    #{name}Code: #{code},\n    #{camel_lower(type)}Name: #{camel_lower(type)}NameForCode(#{code})"
  end

  defp js_field_prop(%{wire_type: {:union, _type}, key: key, name: name}, _index) do
    tag = "payload[constants.KEY_#{macro_name(key <> "_tag")}]"
    value = "payload[constants.KEY_#{macro_name(key <> "_value")}]"

    "    #{name}: { tag: #{tag}, value: #{value} }"
  end

  defp js_field_prop(%{key: key, name: name}, _index) do
    "    #{name}: payload[constants.KEY_#{macro_name(key)}]"
  end

  defp js_encode_field_writes(%{wire_type: {:union, _type}} = field, source) do
    tag_key = "constants.KEY_#{macro_name(field.key <> "_tag")}"
    value_key = "constants.KEY_#{macro_name(field.key <> "_value")}"

    """
          payload[#{tag_key}] = #{source} && #{source}.tag;
          payload[#{value_key}] = #{source} && #{source}.value;
    """
  end

  defp js_encode_field_writes(field, source) do
    "      payload[constants.KEY_#{macro_name(field.key)}] = #{js_encode_field_value(field, source)};"
  end

  defp js_encode_field_value(%{wire_type: :bool}, source),
    do: "(#{source} ? 1 : 0)"

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
