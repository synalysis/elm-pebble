defmodule Elmc.Backend.CCodegen.SchemaRegistry do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Types
  alias ElmEx.IR

  @type field_type :: String.t()
  @type record_schema :: %{
          module: String.t(),
          name: String.t(),
          fields: %{String.t() => field_type()},
          all_native?: boolean(),
          native_field_names: [String.t()]
        }

  @type t :: %__MODULE__{
          records: %{optional({String.t(), String.t()}) => record_schema()},
          union_modules: MapSet.t(String.t())
        }

  defstruct records: %{}, union_modules: MapSet.new()

  @native_field_types MapSet.new(["Int", "Bool", "Char", "Float"])

  @spec build(IR.t()) :: t()
  def build(%IR{} = ir) do
    field_types = IRQueries.record_alias_field_types_map(ir)
    union_names = IRQueries.union_type_name_set(ir)

    records =
      Map.new(field_types, fn {{mod, name}, fields} ->
        normalized =
          fields
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
          |> Map.new()

        native_fields =
          normalized
          |> Enum.filter(fn {_field, type} -> native_field_type?(type) end)
          |> Enum.map(&elem(&1, 0))

        all_native? =
          normalized != %{} and
            Enum.all?(normalized, fn {_field, type} -> native_field_type?(type) end)

        entry = %{
          module: mod,
          name: name,
          fields: normalized,
          all_native?: all_native?,
          native_field_names: native_fields
        }

        {{mod, name}, entry}
      end)

    %__MODULE__{records: records, union_modules: union_names}
  end

  @spec build_from_field_types(Types.record_field_types_map(), MapSet.t(String.t())) :: t()
  def build_from_field_types(field_types, union_names \\ MapSet.new()) when is_map(field_types) do
    records =
      Map.new(field_types, fn {{mod, name}, fields} ->
        normalized =
          fields
          |> Enum.map(fn {k, v} -> {to_string(k), Host.normalize_type_name(to_string(v))} end)
          |> Map.new()

        native_fields =
          normalized
          |> Enum.filter(fn {_field, type} -> native_field_type?(type) end)
          |> Enum.map(&elem(&1, 0))

        all_native? =
          normalized != %{} and
            Enum.all?(normalized, fn {_field, type} -> native_field_type?(type) end)

        {{mod, name}, %{
           module: mod,
           name: name,
           fields: normalized,
           all_native?: all_native?,
           native_field_names: native_fields
         }}
      end)

    %__MODULE__{records: records, union_modules: union_names}
  end

  @spec record(t(), String.t(), String.t()) :: record_schema() | nil
  def record(%__MODULE__{records: records}, mod, name)
      when is_binary(mod) and is_binary(name) do
    Map.get(records, {mod, name})
  end

  @spec all_native?(t(), String.t(), String.t()) :: boolean()
  def all_native?(registry, mod, name) do
    case record(registry, mod, name) do
      %{all_native?: true} -> true
      _ -> false
    end
  end

  @spec list_elem_schema(t(), String.t()) :: StoragePlan.elem_schema() | nil
  def list_elem_schema(_registry, "List Int"), do: {:primitive, :int}
  def list_elem_schema(_registry, "List Float"), do: {:primitive, :float}
  def list_elem_schema(_registry, "List Char"), do: {:primitive, :char}
  def list_elem_schema(_registry, "List Bool"), do: {:primitive, :bool}

  def list_elem_schema(%__MODULE__{} = registry, type) when is_binary(type) do
    type = Host.normalize_type_name(type)

    cond do
      String.starts_with?(type, "List ") ->
        elem_type = String.trim_leading(type, "List ") |> Host.normalize_type_name()
        list_elem_schema_for_type(registry, elem_type)

      true ->
        nil
    end
  end

  defp list_elem_schema_for_type(registry, elem_type) do
    cond do
      elem_type == "Int" -> {:primitive, :int}
      elem_type == "Float" -> {:primitive, :float}
      elem_type == "Char" -> {:primitive, :char}
      elem_type == "Bool" -> {:primitive, :bool}
      record_type?(elem_type) -> record_elem_schema(registry, elem_type)
      true -> {:boxed, :value}
    end
  end

  defp record_elem_schema(registry, type) do
    case String.split(type, ".", parts: 2) do
      [mod, name] ->
        if all_native?(registry, mod, name) do
          {:record, mod, name}
        else
          {:boxed, :value}
        end

      [name] ->
        if all_native?(registry, "Main", name) do
          {:record, "Main", name}
        else
          {:boxed, :value}
        end
    end
  end

  defp record_type?(type) when is_binary(type) do
    not String.starts_with?(type, "Maybe ") and
      not String.starts_with?(type, "Result ") and
      type not in ["String", "Cmd", "Sub"]
  end

  defp native_field_type?(type) when is_binary(type) do
    type
    |> Host.normalize_type_name()
    |> then(&MapSet.member?(@native_field_types, &1))
  end
end
