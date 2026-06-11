defmodule IdeWeb.WorkspaceLive.DebuggerSupport.Util.WireMap do
  @moduledoc false

  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types

  @type wire_map :: Types.wire_map()
  @type runtime_value :: Types.runtime_value()

  @spec map_lookup(wire_map(), atom()) :: {:ok, runtime_value()} | :error
  def map_lookup(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) ->
        {:ok, Map.get(map, key)}

      Map.has_key?(map, string_key) ->
        {:ok, Map.get(map, string_key)}

      true ->
        :error
    end
  end

  def map_lookup(_map, _key), do: :error

  @spec map_string(wire_map(), atom()) :: String.t() | nil
  def map_string(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_binary(value) -> value
      _ -> nil
    end
  end

  @spec map_scalar_string(wire_map(), atom()) :: String.t() | nil
  def map_scalar_string(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, nil} -> nil
      {:ok, value} when is_binary(value) -> value
      {:ok, value} when is_boolean(value) -> to_string(value)
      {:ok, value} when is_integer(value) -> Integer.to_string(value)
      {:ok, value} when is_float(value) -> :erlang.float_to_binary(value, [:compact])
      _ -> nil
    end
  end

  @spec map_integer(wire_map(), atom()) :: integer() | nil
  def map_integer(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_integer(value) -> value
      _ -> nil
    end
  end

  def map_integer(_map, _key), do: nil

  @spec map_map(wire_map(), atom()) :: wire_map()
  def map_map(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  @spec map_list(wire_map(), atom()) :: [runtime_value()]
  def map_list(map, key) when is_map(map) and is_atom(key) do
    case map_lookup(map, key) do
      {:ok, value} when is_list(value) -> value
      _ -> []
    end
  end
end
