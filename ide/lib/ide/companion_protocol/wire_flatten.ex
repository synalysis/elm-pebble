defmodule Ide.CompanionProtocol.WireFlatten do
  @moduledoc false

  alias Ide.CompanionProtocol.WireSchema

  @max_list_elements 16
  @max_dict_entries 16
  @max_nested_depth 4
  @max_keys_per_message 64

  @type wire_type :: WireSchema.wire_type()
  @type wire_slot :: WireSchema.wire_slot()
  @type field :: WireSchema.field()
  @type message :: WireSchema.message()
  @type flatten_context :: WireSchema.flatten_context()
  @type message_build_context :: WireSchema.message_build_context()

  @spec max_list_elements() :: pos_integer()
  def max_list_elements, do: @max_list_elements

  @spec max_dict_entries() :: pos_integer()
  def max_dict_entries, do: @max_dict_entries

  @spec max_nested_depth() :: pos_integer()
  def max_nested_depth, do: @max_nested_depth

  @spec max_keys_per_message() :: pos_integer()
  def max_keys_per_message, do: @max_keys_per_message

  @spec resolve_type(
          String.t(),
          WireSchema.enums(),
          WireSchema.payload_unions(),
          WireSchema.type_aliases()
        ) :: wire_type()
  def resolve_type("Int", _enums, _payload_unions, _aliases), do: :int
  def resolve_type("Bool", _enums, _payload_unions, _aliases), do: :bool
  def resolve_type("String", _enums, _payload_unions, _aliases), do: :string

  def resolve_type("List " <> elem_type, enums, payload_unions, aliases),
    do: {:list, resolve_type(elem_type, enums, payload_unions, aliases)}

  def resolve_type("Dict String " <> value_type, enums, payload_unions, aliases),
    do: {:dict, resolve_type(value_type, enums, payload_unions, aliases)}

  def resolve_type("Dict.Dict String " <> value_type, enums, payload_unions, aliases),
    do: {:dict, resolve_type(value_type, enums, payload_unions, aliases)}

  def resolve_type(type, enums, payload_unions, aliases) do
    cond do
      Map.has_key?(enums, type) ->
        {:enum, type}

      Map.has_key?(payload_unions, type) ->
        ctors = Map.fetch!(payload_unions, type)
        if legacy_union_ctors?(ctors), do: {:union, type}, else: {:union, type, ctors}

      Map.has_key?(aliases, type) ->
        fields =
          aliases
          |> Map.fetch!(type)
          |> Enum.map(fn field ->
            Map.put(field, :wire_type, resolve_type(field.type, enums, payload_unions, aliases))
          end)

        {:record, type, fields}

      true ->
        :int
    end
  end

  @spec field_keys(field(), flatten_context()) :: [String.t()]
  def field_keys(%{wire_type: {:union, type}, key: key}, schema) do
    if legacy_union?(schema, type) do
      [key <> "_tag", key <> "_value"]
    else
      flatten_keys(key, {:union, type}, schema)
    end
  end

  def field_keys(%{wire_type: {:union, type, ctors}, key: key}, schema),
    do: flatten_keys(key, {:union, type, ctors}, schema)

  def field_keys(%{wire_type: {:list, :int}, key: key}, _schema),
    do: [key <> "_count" | Enum.map(0..(@max_list_elements - 1), &"#{key}_#{&1}")]

  def field_keys(%{wire_type: wire_type, key: key}, schema),
    do: flatten_keys(key, wire_type, schema)

  @spec slots_for_field(field(), flatten_context()) :: [wire_slot()]
  def slots_for_field(%{wire_type: wire_type, key: key} = field, schema) do
    flatten_slots(key, wire_type, schema, [%{kind: :field, name: field.name}], 0)
  end

  @spec validate_message_key_count([message()], message_build_context()) ::
          :ok | {:error, {:wire_schema_too_large, WireSchema.wire_schema_too_large_detail()}}
  def validate_message_key_count(messages, schema) do
    case Enum.find(messages, &(length(message_keys(&1, schema)) > @max_keys_per_message)) do
      nil ->
        :ok

      message ->
        {:error,
         {:wire_schema_too_large,
          %{
            message: message.name,
            max_keys: @max_keys_per_message,
            key_count: length(message_keys(message, schema))
          }}}
    end
  end

  @spec message_keys(message(), message_build_context()) :: [String.t()]
  def message_keys(message, schema) do
    message.fields
    |> Enum.flat_map(&field_keys(&1, schema))
    |> Enum.uniq()
  end

  @spec legacy_union?(flatten_context(), String.t()) :: boolean()
  def legacy_union?(schema, type) do
    schema.payload_unions
    |> Map.get(type, [])
    |> Enum.all?(fn
      %{args: []} -> true
      %{args: ["Int"]} -> true
      _ctor -> false
    end)
  end

  @spec flatten_keys(String.t(), wire_type(), flatten_context()) :: [String.t()]
  defp flatten_keys(prefix, wire_type, schema),
    do: Enum.map(flatten_slots(prefix, wire_type, schema, [], 0), & &1.key)

  @spec flatten_slots(
          String.t(),
          wire_type(),
          flatten_context(),
          [WireSchema.path_segment()],
          non_neg_integer()
        ) :: [wire_slot()]
  defp flatten_slots(_prefix, _wire_type, _schema, _path, depth) when depth > @max_nested_depth,
    do: []

  defp flatten_slots(prefix, :int, _schema, path, _depth),
    do: [slot(prefix, :int, :int, path)]

  defp flatten_slots(prefix, :bool, _schema, path, _depth),
    do: [slot(prefix, :bool, :bool, path)]

  defp flatten_slots(prefix, :string, _schema, path, _depth),
    do: [slot(prefix, :string, :string, path)]

  defp flatten_slots(prefix, {:enum, type}, _schema, path, _depth),
    do: [slot(prefix, {:enum, type}, :int, path)]

  defp flatten_slots(prefix, {:record, _name, fields}, schema, path, depth) do
    Enum.flat_map(fields, fn field ->
      flatten_slots(
        "#{prefix}_#{field.name}",
        field.wire_type,
        schema,
        path ++ [%{kind: :record_field, name: field.name}],
        depth + 1
      )
    end)
  end

  defp flatten_slots(prefix, {:list, elem_type}, schema, path, depth) do
    count = slot(prefix <> "_count", :int, :int, path ++ [%{kind: :list_count}], :offset)

    elements =
      0..(@max_list_elements - 1)
      |> Enum.flat_map(fn index ->
        flatten_slots(
          "#{prefix}_#{index}",
          elem_type,
          schema,
          path ++ [%{kind: :list_index, index: index}],
          depth + 1
        )
        |> Enum.map(&Map.put(&1, :wire_offset, scalar_offset(&1)))
      end)

    [count | elements]
  end

  defp flatten_slots(prefix, {:dict, value_type}, schema, path, depth) do
    count = slot(prefix <> "_count", :int, :int, path ++ [%{kind: :dict_count}], :offset)

    entries =
      0..(@max_dict_entries - 1)
      |> Enum.flat_map(fn index ->
        key_slot =
          slot(
            "#{prefix}_key_#{index}",
            :string,
            :string,
            path ++ [%{kind: :dict_key, index: index}]
          )

        value_slots =
          flatten_slots(
            "#{prefix}_val_#{index}",
            value_type,
            schema,
            path ++ [%{kind: :dict_value, index: index}],
            depth + 1
          )
          |> Enum.map(&Map.put(&1, :wire_offset, scalar_offset(&1)))

        [key_slot | value_slots]
      end)

    [count | entries]
  end

  defp flatten_slots(prefix, {:union, type}, schema, path, depth) do
    flatten_union_slots(
      prefix,
      type,
      Map.get(schema.payload_unions, type, []),
      schema,
      path,
      depth
    )
  end

  defp flatten_slots(prefix, {:union, type, ctors}, schema, path, depth) do
    flatten_union_slots(prefix, type, ctors, schema, path, depth)
  end

  @spec flatten_union_slots(
          String.t(),
          String.t(),
          [WireSchema.constructor()],
          flatten_context(),
          [WireSchema.path_segment()],
          non_neg_integer()
        ) :: [wire_slot()]
  defp flatten_union_slots(prefix, type, ctors, schema, path, depth) do
    tag =
      slot(
        prefix <> "_tag",
        {:enum, type},
        :int,
        path ++ [%{kind: :union_tag, type: type}],
        :offset
      )

    variants =
      ctors
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {ctor, tag_code} ->
        ctor.args
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {arg_type, arg_index} ->
          wire_type =
            resolve_type(arg_type, schema.enums, schema.payload_unions, schema.type_aliases)

          child_prefix =
            if length(ctor.args) == 1 and legacy_union?(schema, type) do
              prefix <> "_value"
            else
              "#{prefix}_#{Macro.underscore(ctor.name)}_arg#{arg_index}"
            end

          flatten_slots(
            child_prefix,
            wire_type,
            schema,
            path ++
              [
                %{kind: :union_variant, type: type, name: ctor.name, tag: tag_code},
                %{kind: :union_arg, index: arg_index}
              ],
            depth + 1
          )
        end)
      end)

    [tag | variants]
  end

  @spec slot(
          String.t(),
          wire_type(),
          WireSchema.storage_type(),
          [WireSchema.path_segment()],
          WireSchema.wire_offset()
        ) :: wire_slot()
  defp slot(key, wire_type, storage_type, path, wire_offset \\ :raw) do
    %{
      key: key,
      c_name: c_name(key),
      wire_type: wire_type,
      storage_type: storage_type,
      path: path,
      wire_offset: wire_offset
    }
  end

  defp scalar_offset(%{storage_type: :int}), do: :offset
  defp scalar_offset(slot), do: Map.get(slot, :wire_offset, :raw)

  defp c_name(key) do
    key
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.downcase()
    |> then(&"wire_#{&1}")
  end

  defp legacy_union_ctors?(ctors) do
    Enum.all?(ctors, fn
      %{args: []} -> true
      %{args: ["Int"]} -> true
      _ctor -> false
    end)
  end
end
