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
    %{
      block
      | instrs:
          block.instrs
          |> Enum.reject(&dead_retain?(&1, used))
          |> Enum.reject(&dead_phi_arm_value?(&1, phi_arm_drops))
    }
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
