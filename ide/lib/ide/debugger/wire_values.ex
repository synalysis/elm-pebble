defmodule Ide.Debugger.WireValues do
  @moduledoc """
  Nil-safe coalescing for protocol wire values where `0` and `false` are valid.
  """

  alias Ide.Debugger.Types

  @spec coalesce([Types.wire_input() | nil]) :: Types.wire_input() | nil
  def coalesce(values) when is_list(values) do
    Enum.find(values, fn value -> not is_nil(value) end)
  end

  @spec map_get_first_present(Types.wire_map(), [String.t() | atom()]) :: Types.wire_input() | nil
  def map_get_first_present(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  def map_get_first_present(_map, _keys), do: nil

  @spec map_value(Types.wire_map(), String.t() | atom()) :: Types.wire_input() | nil
  def map_value(map, key) when is_map(map) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      atom_key =
        if is_binary(key) do
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> nil
          end
        else
          nil
        end

      if not is_nil(atom_key) and Map.has_key?(map, atom_key) do
        Map.get(map, atom_key)
      end
    end
  end

  def map_value(_map, _key), do: nil
end
