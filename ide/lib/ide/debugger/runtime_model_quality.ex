defmodule Ide.Debugger.RuntimeModelQuality do
  @moduledoc false

  alias Ide.Debugger.RuntimeArtifacts
  alias Ide.Debugger.Types

  @doc "Public runtime model map with parser-artifact fields removed for display/export."
  @spec public_runtime_model(Types.inner_runtime_model()) :: Types.inner_runtime_model()
  def public_runtime_model(model) when is_map(model) do
    model
    |> RuntimeArtifacts.public_model()
    |> drop_parser_artifacts()
  end

  def public_runtime_model(_model), do: %{}

  @doc "Sorted field names that still contain parser/introspect artifacts."
  @spec unresolved_field_names(Types.inner_runtime_model()) :: [String.t()]
  def unresolved_field_names(model) when is_map(model) do
    model
    |> RuntimeArtifacts.public_model()
    |> unresolved_field_names_on_model()
  end

  def unresolved_field_names(_model), do: []

  @doc false
  @spec findings(Types.inner_runtime_model()) :: [String.t()]
  def findings(model) when is_map(model) do
    case unresolved_field_names(model) do
      [] ->
        []

      fields ->
        [
          "runtime_model_has_parser_artifacts: #{Enum.join(fields, ", ")}"
        ]
    end
  end

  def findings(_model), do: []

  @doc "Drop top-level model fields whose values are parser/introspect artifacts."
  @spec drop_parser_artifacts(Types.inner_runtime_model()) :: Types.inner_runtime_model()
  def drop_parser_artifacts(model) when is_map(model) do
    model
    |> Enum.reject(fn {_key, value} -> unresolved_value?(value) end)
    |> Map.new()
  end

  def drop_parser_artifacts(_model), do: %{}

  @doc false
  @spec unresolved_value?(Types.wire_input()) :: boolean()
  def unresolved_value?(%{"$opaque" => true}), do: true
  def unresolved_value?(%{:"$opaque" => true}), do: true
  def unresolved_value?(%{"$var" => name}) when is_binary(name), do: true
  def unresolved_value?(%{:"$var" => name}) when is_binary(name), do: true
  def unresolved_value?(%{"$field" => field}) when is_binary(field), do: true
  def unresolved_value?(%{:"$field" => field}) when is_binary(field), do: true
  def unresolved_value?(%{"op" => "field_access"}), do: true
  def unresolved_value?(%{op: "field_access"}), do: true
  def unresolved_value?(%{op: :field_access}), do: true
  def unresolved_value?(%{"call" => call}) when is_binary(call), do: true
  def unresolved_value?(%{"$call" => call}) when is_binary(call), do: true
  def unresolved_value?(%{call: call}) when is_binary(call), do: true

  def unresolved_value?(value) when is_map(value) do
    Enum.any?(value, fn {_key, nested} -> unresolved_value?(nested) end)
  end

  def unresolved_value?(value) when is_list(value), do: Enum.any?(value, &unresolved_value?/1)
  def unresolved_value?(value) when is_tuple(value), do: unresolved_value?(Tuple.to_list(value))
  def unresolved_value?(_value), do: false

  @spec unresolved_field_names_on_model(Types.inner_runtime_model()) :: [String.t()]
  defp unresolved_field_names_on_model(model) when is_map(model) do
    model
    |> Enum.filter(fn {_key, value} -> unresolved_value?(value) end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.sort()
  end
end
