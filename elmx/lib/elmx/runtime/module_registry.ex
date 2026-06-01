defmodule Elmx.Runtime.ModuleRegistry do
  @moduledoc """
  In-memory registry of hot-reloaded generated modules keyed by revision or IR hash.
  """

  use Agent

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec put(String.t(), module()) :: :ok
  def put(key, module) when is_binary(key) and is_atom(module) do
    Agent.update(__MODULE__, &Map.put(&1, key, module))
  end

  @spec get(String.t()) :: module() | nil
  def get(key) when is_binary(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  @spec delete(String.t()) :: :ok
  def delete(key) when is_binary(key) do
    Agent.update(__MODULE__, &Map.delete(&1, key))
    :ok
  end
end
