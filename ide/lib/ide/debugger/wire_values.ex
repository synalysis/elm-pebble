defmodule Ide.Debugger.WireValues do
  @moduledoc """
  Nil-safe coalescing for protocol wire values where `0` and `false` are valid.
  """

  @spec coalesce([term()]) :: term() | nil
  def coalesce(values) when is_list(values) do
    Enum.find(values, fn value -> not is_nil(value) end)
  end

  @spec map_get_first_present(map(), [String.t() | atom()]) :: term() | nil
  def map_get_first_present(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  def map_get_first_present(_map, _keys), do: nil
end
