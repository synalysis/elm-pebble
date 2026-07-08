defmodule Elmc.Backend.Plan.Allocate do
  @moduledoc """
  Register → owned-slot allocation from plan liveness.

  C backend uses `owned[i]` indices; bytecode uses local indices;
  both derive from the same liveness pass.
  """

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @type slot_map :: %{Types.reg() => non_neg_integer()}

  @spec run(FunctionPlan.t()) :: {slot_map(), non_neg_integer()}
  def run(%FunctionPlan{blocks: blocks, reg_count: reg_count}) do
    live = liveness(blocks, reg_count)
    allocate_slots(live, reg_count)
  end

  defp liveness(blocks, reg_count) do
    # Last-use index per register (simple linear scan)
    uses = List.duplicate(-1, reg_count)

    {uses, _} =
      Enum.reduce(blocks, {uses, 0}, fn %Block{instrs: instrs}, {acc, idx} ->
        Enum.reduce(instrs, {acc, idx}, fn instr, {u, i} ->
          u1 = mark_uses(u, instr)
          {u1, i + 1}
        end)
      end)

    uses
  end

  defp mark_uses(uses, %Types{effects: fx, dest: dest}) do
    uses
    |> mark_reg_list(fx.borrows || [])
    |> mark_reg_list(fx.consumes || [])
    |> mark_dest(dest)
  end

  defp mark_reg_list(uses, regs) do
    Enum.reduce(regs, uses, fn
      r, acc when is_integer(r) and r < length(acc) ->
        List.replace_at(acc, r, r)

      _, acc ->
        acc
    end)
  end

  defp mark_dest(uses, r) when is_integer(r) and r < length(uses), do: List.replace_at(uses, r, r)
  defp mark_dest(uses, _), do: uses

  defp allocate_slots(live, _reg_count) do
  needs_slot? =
    live
    |> Enum.with_index()
    |> Enum.filter(fn {last, _i} -> last >= 0 end)
    |> Enum.map(&elem(&1, 1))

  {slot_map, next} =
    Enum.reduce(needs_slot?, {%{}, 0}, fn reg, {map, n} ->
      {Map.put(map, reg, n), n + 1}
    end)

  {slot_map, next}
  end
end
