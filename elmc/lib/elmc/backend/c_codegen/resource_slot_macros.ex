defmodule Elmc.Backend.CCodegen.ResourceSlotMacros do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias ElmEx.IR

  @spec define_lines(IR.t()) :: [{String.t(), pos_integer()}]
  def define_lines(%IR{} = ir) do
    ir
    |> slot_map()
    |> Enum.sort_by(fn {name, _index} -> name end)
    |> Enum.map(fn {name, index} ->
      {macro_name(name), index}
    end)
  end

  @spec literal_ref(Types.ir_expr()) :: String.t() | nil
  def literal_ref(%{op: :int_literal, union_ctor: ctor}) when is_binary(ctor) do
    short = short_ctor_name(ctor)

    if Map.has_key?(slot_map(), short) do
      macro_name(short)
    end
  end

  def literal_ref(_expr), do: nil

  @spec macro_name(String.t()) :: String.t()
  def macro_name(name) when is_binary(name) do
    suffix =
      name
      |> short_ctor_name()
      |> Util.safe_c_suffix()
      |> String.upcase()

    "ELMC_RESOURCE_SLOT_#{suffix}"
  end

  defp slot_map do
    Enum.reduce(
      [
        :elmc_vector_resource_slots,
        :elmc_bitmap_resource_slots,
        :elmc_animation_resource_slots,
        :elmc_font_resource_slots
      ],
      %{},
      fn key, acc ->
        case Process.get(key, %{}) do
          %{} = slots -> Map.merge(acc, slots)
          _ -> acc
        end
      end
    )
  end

  defp slot_map(%IR{} = ir) do
    alias Elmc.Backend.CCodegen.IRQueries

    IRQueries.pebble_vector_resource_slot_map(ir)
    |> Map.merge(IRQueries.pebble_bitmap_resource_slot_map(ir))
    |> Map.merge(IRQueries.pebble_animation_resource_slot_map(ir))
    |> Map.merge(IRQueries.pebble_font_resource_slot_map(ir))
  end

  defp short_ctor_name(ctor) when is_binary(ctor) do
    ctor |> String.split(".") |> List.last()
  end
end
