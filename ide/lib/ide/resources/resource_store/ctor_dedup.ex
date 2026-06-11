defmodule Ide.Resources.ResourceStore.CtorDedup do
  @moduledoc false

  alias Ide.Resources.Types

  @spec among_entries(String.t(), [Types.manifest_wire_row()], String.t() | nil) :: String.t()
  def among_entries(_ctor, _entries, ctor_hint) when is_binary(ctor_hint) and ctor_hint != "" do
    ctor_hint
  end

  def among_entries(ctor, entries, _ctor_hint) when is_binary(ctor) and is_list(entries) do
    used =
      entries
      |> Enum.map(&Map.get(&1, "ctor", ""))
      |> MapSet.new()

    if MapSet.member?(used, ctor) do
      Stream.iterate(2, &(&1 + 1))
      |> Enum.find_value(fn idx ->
        candidate = "#{ctor}#{idx}"
        if MapSet.member?(used, candidate), do: nil, else: candidate
      end)
    else
      ctor
    end
  end
end
