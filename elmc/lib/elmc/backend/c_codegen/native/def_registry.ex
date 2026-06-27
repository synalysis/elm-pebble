defmodule Elmc.Backend.CCodegen.Native.DefRegistry do
  @moduledoc false

  @key :elmc_required_native_defs

  @spec reset() :: :ok
  def reset do
    Process.put(@key, MapSet.new())
    :ok
  end

  @spec required?({String.t(), String.t()}) :: boolean()
  def required?({mod, name}) do
    MapSet.member?(Process.get(@key, MapSet.new()), {mod, name})
  end

  @spec mark_required({String.t(), String.t()}) :: :ok
  def mark_required({mod, name}) when is_binary(mod) and is_binary(name) do
    current = Process.get(@key, MapSet.new())
    Process.put(@key, MapSet.put(current, {mod, name}))
    :ok
  end
end
