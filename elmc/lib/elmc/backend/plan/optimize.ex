defmodule Elmc.Backend.Plan.Optimize do
  @moduledoc false

  alias Elmc.Backend.Plan.{IntPhiNative, TruthyNative}
  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan}

  @spec run(FunctionPlan.t()) :: FunctionPlan.t()
  def run(%FunctionPlan{blocks: blocks} = plan) do
    blocks = Enum.map(blocks, &coalesce_arm_publish_block/1)

    used = used_regs(blocks)
    phi_arm_drops =
      MapSet.union(
        TruthyNative.phi_arm_drop_instrs(blocks),
        IntPhiNative.phi_arm_drop_instrs(blocks)
      )

    %{plan | blocks: Enum.map(blocks, &optimize_block(&1, used, phi_arm_drops))}
  end

  defp coalesce_arm_publish_block(%Block{instrs: instrs} = block) do
    %{block | instrs: coalesce_arm_publish_instrs(instrs)}
  end

  defp coalesce_arm_publish_instrs(instrs) when is_list(instrs) do
    case Enum.split(instrs, -2) do
      {prefix,
       [
         %{op: :call_fn, dest: arm_reg} = call,
         %{
           op: :call_runtime,
           dest: merge_reg,
           args: %{builtin: :retain, args: [src_reg]},
           effects: %{consumes: consumes}
         }
       ]}
      when is_integer(arm_reg) and is_integer(merge_reg) and is_integer(src_reg) and
             arm_reg == src_reg and arm_reg != merge_reg and consumes == [arm_reg] ->
        prefix ++ [%{call | dest: merge_reg}]

      _ ->
        instrs
    end
  end

  defp optimize_block(%Block{} = block, used, phi_arm_drops) do
    instrs =
      block.instrs
      |> Enum.reject(&dead_retain?(&1, used))
      |> Enum.reject(&dead_phi_arm_value?(&1, phi_arm_drops))
      |> drop_unread_overwritten_defs(block.terminator)

    %{block | instrs: instrs}
  end

  defp drop_unread_overwritten_defs(instrs, terminator) when is_list(instrs) do
    {dead, _} = unread_overwritten_indices(instrs, terminator)

    instrs
    |> Enum.with_index()
    |> Enum.reject(fn {_, idx} -> MapSet.member?(dead, idx) end)
    |> Enum.map(fn {instr, _} -> instr end)
  end

  @doc false
  @spec unread_overwritten_dest_regs([map()], term()) :: MapSet.t()
  def unread_overwritten_dest_regs(instrs, terminator) when is_list(instrs) do
    {dead, _} = unread_overwritten_indices(instrs, terminator)

    dead
    |> Enum.flat_map(fn idx ->
      case Enum.at(instrs, idx) do
        %{dest: dest} when is_integer(dest) -> [dest]
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  defp unread_overwritten_indices(instrs, terminator) when is_list(instrs) do
    final_reads = terminator |> terminator_uses() |> MapSet.new()

    {dead, state} =
      Enum.reduce(Enum.with_index(instrs), {MapSet.new(), %{}}, fn {instr, idx}, {dead, state} ->
        state = mark_operand_reads(instr, state)

        case Map.get(instr, :dest) do
          dest when is_integer(dest) ->
            {dead, state} =
              case Map.get(state, dest) do
                %{def_idx: def_idx, read: false, instr: prev} when is_map(prev) ->
                  dead =
                    if removable_overwritten_def?(prev),
                      do: MapSet.put(dead, def_idx),
                      else: dead

                  {dead, Map.put(state, dest, %{def_idx: idx, read: false, instr: instr})}

                _ ->
                  {dead, Map.put(state, dest, %{def_idx: idx, read: false, instr: instr})}
              end

            {dead, state}

          _ ->
            {dead, state}
        end
      end)

    dead =
      Enum.reduce(final_reads, dead, fn reg, dead_acc ->
        case Map.get(state, reg) do
          %{def_idx: idx} -> MapSet.delete(dead_acc, idx)
          _ -> dead_acc
        end
      end)

    {dead, state}
  end

  defp removable_overwritten_def?(%{op: :const_int}), do: true

  defp removable_overwritten_def?(%{op: :call_runtime, args: %{builtin: builtin}})
       when builtin in [:retain, :new_int],
       do: true

  defp removable_overwritten_def?(_), do: false

  defp mark_operand_reads(instr, state) do
    Enum.reduce(operand_regs(instr), state, fn reg, acc ->
      case Map.get(acc, reg) do
        %{def_idx: _def_idx} = entry -> Map.put(acc, reg, %{entry | read: true})
        _ -> acc
      end
    end)
  end

  defp dead_phi_arm_value?(%{dest: dest, block_id: block_id}, phi_arm_drops)
       when is_integer(dest) and is_integer(block_id) do
    MapSet.member?(phi_arm_drops, {dest, block_id})
  end

  defp dead_phi_arm_value?(_, _), do: false

  defp dead_retain?(
         %{
           op: :call_runtime,
           dest: dest,
           args: %{builtin: :retain, args: [_src]}
         },
         used
       )
       when is_integer(dest) do
    not MapSet.member?(used, dest)
  end

  defp dead_retain?(_, _), do: false

  defp used_regs(blocks) do
    blocks
    |> Enum.flat_map(fn %Block{instrs: instrs, terminator: term} ->
      instr_uses(instrs) ++ terminator_uses(term)
    end)
    |> Enum.filter(&is_integer/1)
    |> MapSet.new()
  end

  defp instr_uses(instrs) do
    Enum.flat_map(instrs, fn
      %Types{dest: dest} = instr when is_integer(dest) ->
        operand_regs(instr) ++ [dest]

      instr ->
        operand_regs(instr)
    end)
  end

  defp terminator_uses({:br_if, _, _, cond}) when is_integer(cond), do: [cond]
  defp terminator_uses({:switch_tag, subject, _, _}) when is_integer(subject), do: [subject]
  defp terminator_uses({:ret, reg}) when is_integer(reg), do: [reg]
  defp terminator_uses(_), do: []

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r, cond: cond}}),
    do: [then_r, else_r, cond]

  defp operand_regs(%{op: :phi, args: %{then: then_r, else: else_r}}), do: [then_r, else_r]

  defp operand_regs(%{effects: %{borrows: borrows, consumes: consumes}}) do
    (borrows || []) ++ (consumes || [])
  end

  defp operand_regs(%{args: %{args: args}}) when is_list(args), do: args
  defp operand_regs(%{args: %{lhs: lhs, rhs: rhs}}), do: [lhs, rhs]
  defp operand_regs(%{args: %{base: base}}) when is_integer(base), do: [base]
  defp operand_regs(%{args: %{source: source}}) when is_integer(source), do: [source]
  defp operand_regs(%{args: %{subject: subject}}) when is_integer(subject), do: [subject]
  defp operand_regs(%{args: %{regs: regs}}) when is_list(regs), do: regs
  defp operand_regs(%{args: %{params: params}}) when is_list(params), do: params
  defp operand_regs(_), do: []
end
