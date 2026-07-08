defmodule Elmc.Backend.Plan.Lower.Case.GuardedSwitch do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case.ArmMerge
  alias Elmc.Backend.Plan.Lower.{Expr, PatternBind, PatternMatch}
  alias Elmc.Backend.Plan.Types

  @spec branches?(list()) :: boolean()
  def branches?(branches) when is_list(branches) do
    length(branches) >= 2 and
      Enum.all?(branches, fn branch ->
        guardable_pattern?(Map.get(branch, :pattern))
      end)
  end

  def branches?(_), do: false

  @spec compile(map(), list(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile(subject, branches, ctx, b) do
    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b),
         b_sealed = seal_entry_block(b1) do
      compile_cfg(subj_reg, branches, ctx, b_sealed)
    else
      _ -> :unsupported
    end
  end

  defp seal_entry_block(b) do
    if b.current_block.instrs != [] or b.current_block.terminator != :none do
      Builder.finish_block(b, :none)
    else
      b
    end
  end

  defp compile_cfg(subj_reg, branches, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)
    {tested, default_br} = split_branches(branches)
    {merge_reg, b0} = Builder.fresh_reg(b)
    entry_id = b0.current_block.id

    with {:ok, arm_exits, default_block_id, b_chain} <-
           compile_test_chain(tested, subj_reg, ctx, b0, merge_reg, entry_id),
         {:ok, default_exit, b_default} <-
           compile_arm(default_br, subj_reg, ctx, b_chain, default_block_id, merge_reg),
         merge_id = skip_reserved(b_default.next_block, saved_pending),
         b_reserved = %{b_default | next_block: max(b_default.next_block, merge_id + 1)},
         b_br = patch_arm_exits(b_reserved, arm_exits ++ List.wrap(default_exit), merge_id),
         b_merge_start = Builder.begin_block(b_br, merge_id),
         {:ok, merge, b_merge} <- ArmMerge.finish_merge(b_merge_start, merge_reg, merge_id) do
      {:ok, merge, %{b_merge | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp split_branches([only]), do: {[], only}

  defp split_branches(branches) do
    {Enum.drop(branches, -1), List.last(branches)}
  end

  defp compile_test_chain([], _subj, _ctx, b, _merge, default_id),
    do: {:ok, [], default_id, b}

  defp compile_test_chain([branch | rest], subj_reg, ctx, b, merge_reg, test_block_id) do
    b_test =
      if b.current_block.id == test_block_id do
        b
      else
        Builder.begin_block(b, test_block_id)
      end

    with {:ok, cond_reg, b1} <-
           PatternMatch.match_condition(Map.get(branch, :pattern), subj_reg, b_test),
         arm_id = b1.next_block,
         else_id = arm_id + 1,
         b1 = %{b1 | next_block: max(b1.next_block, else_id + 1)},
         b_sealed = Builder.finish_block(b1, {:br_if, arm_id, else_id, cond_reg}),
         {:ok, arm_exit, b_arm} <- compile_arm(branch, subj_reg, ctx, b_sealed, arm_id, merge_reg),
         {:ok, more_exits, next_default, b_else} <-
           compile_test_chain(rest, subj_reg, ctx, b_arm, merge_reg, else_id) do
      {:ok, [arm_exit | more_exits], next_default, b_else}
    else
      _ -> :unsupported
    end
  end

  defp compile_arm(branch, subj_reg, ctx, b, arm_id, merge_reg) do
    b_arm =
      if b.current_block.id == arm_id do
        b
      else
        Builder.begin_block(b, arm_id)
      end
    pattern = Map.get(branch, :pattern, %{})
    expr = Map.get(branch, :expr)

    with {:ok, arm_ctx, b1} <- bind_pattern(ctx, b_arm, pattern, subj_reg),
         {:ok, reg, b2} <- Expr.compile(expr, arm_ctx, b1),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b2, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b_done = Builder.finish_block(b_pub, :none) do
      {:ok, exit_id, b_done}
    else
      _ -> :unsupported
    end
  end

  defp bind_pattern(ctx, b, pattern, subj_reg) do
    case PatternBind.bind(pattern, ctx, b, subj_reg) do
      {:ok, ctx1, b1} -> {:ok, ctx1, b1}
      :unsupported -> {:ok, ctx, b}
    end
  end

  defp patch_arm_exits(b, exit_ids, merge_id) when is_list(exit_ids) do
    exit_ids
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(b, fn exit_id, b_acc ->
      Builder.patch_terminator(b_acc, exit_id, {:br, merge_id})
    end)
  end

  defp guardable_pattern?(%{kind: kind})
       when kind in [:tuple, :constructor, :wildcard, :var, :int],
       do: true

  defp guardable_pattern?(_), do: false

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id
end
