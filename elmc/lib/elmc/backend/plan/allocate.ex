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
    instrs = linear_instrs(blocks)
    intervals = live_intervals(instrs, reg_count)
    greedy_slots(intervals)
  end

  defp linear_instrs(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs, terminator: term} ->
      instrs ++ [terminator_instr(term)]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.with_index()
  end

  defp terminator_instr({:br_if, _then_id, _else_id, cond}), do: %{terminator: true, uses: [cond]}
  defp terminator_instr({:switch_tag, subject, _arms, _default}), do: %{terminator: true, uses: [subject]}
  defp terminator_instr(_), do: nil

  defp live_intervals(instrs, reg_count) do
    first = List.duplicate(nil, reg_count)
    last = List.duplicate(-1, reg_count)

    {first, last} =
      Enum.reduce(instrs, {first, last}, fn {instr, idx}, {f_acc, l_acc} ->
        {f_acc, l_acc}
        |> mark_uses(instr, idx)
        |> mark_def(Map.get(instr, :dest), idx)
      end)

    intervals =
      if reg_count <= 0 do
        %{}
      else
        0..(reg_count - 1)
        |> Enum.map(fn reg ->
          case Enum.at(first, reg) do
            start when is_integer(start) ->
              finish = Enum.at(last, reg)
              {reg, {start, max(finish, start)}}

            _ ->
              {reg, nil}
          end
        end)
        |> Enum.reject(fn {_, interval} -> is_nil(interval) end)
        |> Map.new()
      end

    intervals
  end

  defp mark_uses({first, last}, %{terminator: true, uses: uses}, idx) when is_list(uses) do
    Enum.reduce(uses, {first, last}, fn
      r, acc when is_integer(r) -> touch_use(acc, r, idx)
      _, acc -> acc
    end)
  end

  defp mark_uses({first, last}, %{effects: fx} = instr, idx) do
    regs =
      (fx.borrows || []) ++
        (fx.consumes || []) ++ operand_regs(instr)

    Enum.reduce(regs, {first, last}, fn
      r, acc when is_integer(r) -> touch_use(acc, r, idx)
      _, acc -> acc
    end)
  end

  defp mark_uses(acc, %{terminator: true}, _idx), do: acc
  defp mark_uses(acc, _, _idx), do: acc

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r, cond: cond}}),
    do: [then_r, else_r, cond]

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r}}), do: [then_r, else_r]
  defp operand_regs(%{args: %{args: args}}) when is_list(args), do: args
  defp operand_regs(%{args: %{lhs: lhs, rhs: rhs}}), do: [lhs, rhs]
  defp operand_regs(%{args: %{base: base}}) when is_integer(base), do: [base]
  defp operand_regs(%{args: %{source: source}}) when is_integer(source), do: [source]
  defp operand_regs(%{args: %{subject: subject}}) when is_integer(subject), do: [subject]
  defp operand_regs(_), do: []

  defp mark_def({first, last}, reg, idx) when is_integer(reg) do
    f =
      case Enum.at(first, reg) do
        nil -> List.replace_at(first, reg, idx)
        _ -> first
      end

    {f, List.replace_at(last, reg, idx)}
  end

  defp mark_def(acc, _, _), do: acc

  defp touch_use({first, last}, reg, idx) when is_integer(reg) and reg < length(last) do
  f =
    case Enum.at(first, reg) do
      nil -> List.replace_at(first, reg, idx)
      _ -> first
    end

    {f, List.replace_at(last, reg, max(Enum.at(last, reg), idx))}
  end

  defp touch_use(acc, _, _), do: acc

  defp greedy_slots(intervals) when map_size(intervals) == 0, do: {%{}, 0}

  defp greedy_slots(intervals) do
    regs =
      intervals
      |> Map.keys()
      |> Enum.sort_by(fn reg ->
        {start, _finish} = Map.fetch!(intervals, reg)
        start
      end)

    {slot_map, _free, _max} =
      Enum.reduce(regs, {%{}, [], -1}, fn reg, {map, free, max} ->
        {start, finish} = Map.fetch!(intervals, reg)

        {slot, free1, max1} =
          case first_free_slot(free, start) do
            {:ok, slot, rest} ->
              {slot, rest, max}

            :none ->
              slot = max + 1
              {slot, free, slot}
          end

        free2 = sort_free([{slot, finish} | free1])

        {Map.put(map, reg, slot), free2, max1}
      end)

    slot_count =
      case Map.values(slot_map) do
        [] -> 0
        indices -> Enum.max(indices) + 1
      end

    {slot_map, slot_count}
  end

  defp first_free_slot(free, start) do
    case Enum.find(free, fn {_slot, avail} -> avail < start end) do
      {slot, _} = hit -> {:ok, slot, List.delete(free, hit)}
      nil -> :none
    end
  end

  defp sort_free(free), do: Enum.sort_by(free, fn {slot, _} -> slot end)
end
