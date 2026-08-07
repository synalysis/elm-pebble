defmodule Ide.Resources.SlotOrder do
  @moduledoc """
  Shared constructor ordering for generated `Resources.elm` unions and Pebble
  `resource_ids.h` slot switches.

  Elm nullary resource tags follow declaration order in `Pebble.Ui.Resources`.
  Staging must assign the same 1-based indices or `drawVectorAt` loads the wrong PDC.
  """

  alias Ide.Resources.CtorNaming

  @type kind :: :bitmap | :font | :vector | :animation

  @spec sort_wire_entries([map()], kind()) :: [map()]
  def sort_wire_entries(entries, kind) when is_list(entries) and kind in [:bitmap, :font, :vector, :animation] do
    Enum.sort_by(entries, fn row ->
      ctor = entry_ctor(row)
      sort_key(ctor, kind)
    end)
  end

  @spec sort_key(String.t(), kind()) :: {non_neg_integer(), String.t()}
  def sort_key(ctor, :font) when is_binary(ctor), do: {0, ctor}

  def sort_key(ctor, :bitmap) when is_binary(ctor) do
    {prefix_rank(ctor, CtorNaming.prefix(:bitmap_static)), ctor}
  end

  def sort_key(ctor, :animation) when is_binary(ctor) do
    {prefix_rank(ctor, CtorNaming.prefix(:bitmap_animated)), ctor}
  end

  def sort_key(ctor, :vector) when is_binary(ctor) do
    rank =
      cond do
        String.starts_with?(ctor, CtorNaming.prefix(:vector_static)) -> 0
        String.starts_with?(ctor, CtorNaming.prefix(:vector_animated)) -> 1
        true -> 2
      end

    {rank, ctor}
  end

  defp entry_ctor(row) when is_map(row) do
    to_string(Map.get(row, "ctor") || Map.get(row, :ctor) || "")
  end

  defp prefix_rank(ctor, expected_prefix)
       when is_binary(ctor) and is_binary(expected_prefix) do
    if String.starts_with?(ctor, expected_prefix), do: 0, else: 1
  end
end
