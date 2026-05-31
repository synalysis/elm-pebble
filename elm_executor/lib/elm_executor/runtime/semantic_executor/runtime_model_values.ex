defmodule ElmExecutor.Runtime.SemanticExecutor.RuntimeModelValues do
  @moduledoc false

  @doc """
  True when a runtime model value is a static parser/introspect artifact, not an evaluated Elm value.
  """
  @spec parser_artifact?(term()) :: boolean()
  def parser_artifact?(value), do: unresolved_value?(value)

  @spec unresolved_value?(term()) :: boolean()
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

  def unresolved_value?(value) when is_list(value),
    do: Enum.any?(value, &unresolved_value?/1)

  def unresolved_value?(_value), do: false

  @spec unresolved_model?(map()) :: boolean()
  def unresolved_model?(model) when is_map(model) do
    Enum.any?(model, fn {_key, value} -> unresolved_value?(value) end)
  end

  def unresolved_model?(_model), do: false

  @doc "Drop model fields whose values are parser artifacts."
  @spec drop_parser_artifacts(map()) :: map()
  def drop_parser_artifacts(model) when is_map(model) do
    model
    |> Enum.reject(fn {_key, value} -> unresolved_value?(value) end)
    |> Map.new()
  end

  def drop_parser_artifacts(_model), do: %{}

  @doc "Field names on `model` that still hold parser artifacts."
  @spec unresolved_field_names(map()) :: [String.t()]
  def unresolved_field_names(model) when is_map(model) do
    model
    |> Enum.filter(fn {_key, value} -> unresolved_value?(value) end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.sort()
  end

  def unresolved_field_names(_model), do: []
end
