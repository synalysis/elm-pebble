defmodule Elmc.Backend.Plan.Lower.Case.IntSwitch do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case.ArmMerge
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec branches?(list()) :: boolean()
  def branches?(branches) when is_list(branches) do
    tagged? =
      Enum.any?(branches, fn branch ->
        match?(%{pattern: %{kind: :int, value: value}} when is_integer(value), branch)
      end)

    tagged? and
      Enum.all?(branches, fn branch ->
        case Map.get(branch, :pattern) do
          %{kind: :wildcard} -> true
          %{kind: :int, value: value} when is_integer(value) -> true
          _ -> false
        end
      end)
  end

  def branches?(_), do: false

  @spec compile(map(), list(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def compile(subject, branches, ctx, b) do
    with {:ok, subj_reg, b1} <- Expr.compile(subject, ctx, b) do
      compile_cfg(subj_reg, branches, ctx, b1)
    else
      _ -> :unsupported
    end
  end

  defp compile_cfg(subj_reg, branches, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)
    {tagged, default_br} = split_branches(branches)
    entry_id = b.current_block.id
    b_sealed = Builder.finish_block(b, :none)
    {merge_reg, b_sealed} = Builder.fresh_reg(b_sealed)

    with {:ok, tagged_results, _default_reg, default_arm_id, arm_exits, b_arms} <-
           compile_arm_blocks(tagged, default_br, ctx, b_sealed, merge_reg),
         merge_id = skip_reserved(b_arms.next_block, saved_pending),
         b_br = patch_arm_exits(b_arms, arm_exits, merge_id),
         switch_arms = Enum.map(tagged_results, fn {tag, _reg, arm_id} -> {tag, arm_id} end),
         default_block_id = default_arm_id || merge_id,
         b_entry =
           Builder.patch_terminator(
             b_br,
             entry_id,
             {:switch_tag, subj_reg, switch_arms, default_block_id}
           ),
         b_merge_start = Builder.begin_block(b_entry, merge_id),
         {:ok, merge, b_merge} <- ArmMerge.finish_merge(b_merge_start, merge_reg, merge_id) do
      {:ok, merge, %{b_merge | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp split_branches(branches) do
    tagged = Enum.filter(branches, fn br -> match?(%{pattern: %{kind: :int}}, br) end)
    default = Enum.find(branches, fn br -> match?(%{pattern: %{kind: :wildcard}}, br) end)
    {tagged, default}
  end

  defp compile_arm_blocks(tagged, default_br, ctx, b, merge_reg) do
    with {:ok, tagged_results, arm_exits, b1} <- compile_tagged_arms(tagged, ctx, b, merge_reg, []),
         {:ok, default_arm_id, default_exit, b2} <-
           compile_default_arm(default_br, ctx, b1, merge_reg) do
      {:ok, tagged_results, nil, default_arm_id, arm_exits ++ List.wrap(default_exit), b2}
    else
      _ -> :unsupported
    end
  end

  defp compile_tagged_arms([], _ctx, b, _merge_reg, acc), do: {:ok, Enum.reverse(acc), [], b}

  defp compile_tagged_arms([branch | rest], ctx, b, merge_reg, acc) do
    arm_id = b.next_block
    b_arm = Builder.begin_block(b, arm_id)

    with {:ok, reg, tag, b1} <- compile_one_arm(branch, ctx, b_arm),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b1, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b2 = Builder.finish_block(b_pub, :none),
         {:ok, more, exits, b3} <- compile_tagged_arms(rest, ctx, b2, merge_reg, [{tag, reg, arm_id} | acc]) do
      {:ok, more, [exit_id | exits], b3}
    else
      _ -> :unsupported
    end
  end

  defp compile_default_arm(nil, _ctx, b, _merge_reg), do: {:ok, nil, nil, b}

  defp compile_default_arm(branch, ctx, b, merge_reg) do
    arm_id = b.next_block
    b_arm = Builder.begin_block(b, arm_id)

    with {:ok, reg, _tag, b1} <- compile_one_arm(branch, ctx, b_arm),
         {:ok, b_pub} <- ArmMerge.publish_arm_to_merge(b1, reg, merge_reg),
         exit_id = b_pub.current_block.id,
         b2 = Builder.finish_block(b_pub, :none) do
      {:ok, arm_id, exit_id, b2}
    else
      _ -> :unsupported
    end
  end

  defp compile_one_arm(branch, ctx, b) do
    pattern = Map.get(branch, :pattern, %{})
    expr = Map.get(branch, :expr)
    branch_ctx = ctx

    case pattern do
      %{kind: :wildcard} ->
        case Expr.compile(expr, branch_ctx, b) do
          {:ok, reg, b1} -> {:ok, reg, nil, b1}
          :unsupported -> :unsupported
        end

      %{kind: :int, value: value} when is_integer(value) ->
        case Expr.compile(expr, branch_ctx, b) do
          {:ok, reg, b1} -> {:ok, reg, value, b1}
          :unsupported -> :unsupported
        end

      _ ->
        :unsupported
    end
  end

  defp patch_arm_exits(b, exit_ids, merge_id) when is_list(exit_ids) do
    Enum.reduce(exit_ids, b, fn exit_id, b_acc ->
      Builder.patch_terminator(b_acc, exit_id, {:br, merge_id})
    end)
  end

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id
end
