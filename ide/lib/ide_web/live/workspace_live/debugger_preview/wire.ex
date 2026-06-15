defmodule IdeWeb.WorkspaceLive.DebuggerPreview.Wire do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: PreviewTypes

  @type wire_value :: PreviewTypes.wire_value()
  @type wire_map :: PreviewTypes.wire_map()

  @spec first_map([wire_value()]) :: wire_map()
  def first_map(values) when is_list(values) do
    Enum.find(values, %{}, &is_map/1)
  end

  @spec first_present([wire_value()]) :: wire_value()
  def first_present(values) when is_list(values) do
    Enum.find(values, fn value -> not is_nil(value) end)
  end

  @spec map_get_any(wire_map() | nil, String.t()) :: wire_value()
  def map_get_any(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> map_value_by_atom_name(map, key)
    end
  end

  def map_get_any(_map, _key), do: nil

  @spec dimension_int(wire_value(), pos_integer()) :: pos_integer()
  def dimension_int(value, _fallback) when is_integer(value) and value > 0, do: value

  def dimension_int(value, _fallback) when is_float(value) and value > 0,
    do: max(1, trunc(value))

  def dimension_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  def dimension_int(_value, fallback), do: fallback

  @spec boolean_value?(wire_value()) :: boolean()
  def boolean_value?(value) when value in [true, 1, "true", "True", "TRUE"], do: true
  def boolean_value?(_value), do: false

  @spec map_value_by_atom_name(wire_map(), String.t()) :: wire_value()
  defp map_value_by_atom_name(map, key) when is_map(map) and is_binary(key) do
    Enum.find_value(map, fn
      {atom_key, value} when is_atom(atom_key) ->
        if Atom.to_string(atom_key) == key, do: value, else: nil

      _ ->
        nil
    end)
  end
end
