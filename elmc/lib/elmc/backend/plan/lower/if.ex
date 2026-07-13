defmodule Elmc.Backend.Plan.Lower.If do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, ConstantFold, Context, IntPhiNative, TruthyNative}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec compile(Types.ir_expr(), Context.t(), Builder.t()) :: Types.compile_result()
  def compile(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}, ctx, b) do
    compile_branches(cond, then_expr, else_expr, ctx, b)
  end

  def compile(%{op: :if, cond: cond, then: then_expr, else: else_expr}, ctx, b) do
    compile_branches(cond, then_expr, else_expr, ctx, b)
  end

  def compile(_, _, _), do: :unsupported

  defp compile_branches(cond, then_expr, else_expr, ctx, b) do
    case ConstantFold.bool_value(cond, ctx) do
      :unknown ->
        compile_branches_cfg(cond, then_expr, else_expr, ctx, b)

      true ->
        Expr.compile(then_expr, ctx, b)

      false ->
        Expr.compile(else_expr, ctx, b)
    end
  end

  defp compile_branches_cfg(cond, then_expr, else_expr, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)

    with {:ok, cond_reg, b1} <- Expr.compile(cond, ctx, b),
         then_id = b1.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b1, {:br_if, then_id, else_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, then_reg, then_exit, b_then} <- compile_branch(then_expr, ctx, b_reserved, then_id),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         {:ok, else_reg, else_exit, b_else} <-
           compile_branch(else_expr, ctx, b_then_done, else_id),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <- emit_phi(cond_reg, then_reg, else_reg, then_id, else_id, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp compile_branch(expr, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    case Expr.compile(expr, arm_ctx, b_arm) do
      {:ok, reg, b1} ->
        exit_id = b1.current_block.id
        {:ok, reg, exit_id, Builder.finish_block(b1, :none)}

      :unsupported ->
        :unsupported
    end
  end

  defp emit_phi(cond_reg, then_reg, else_reg, then_arm_block, else_arm_block, b) do
    {merge, b1} = Builder.fresh_reg(b)
    instrs = builder_instrs(b1)

    {native_int_phi?, int_then_shape, int_else_shape} =
      IntPhiNative.native_int_phi_shapes?(instrs, then_reg, else_reg)

    {truthy_native?, then_shape, else_shape} =
      if native_int_phi? do
        {false, :unknown, :unknown}
      else
        TruthyNative.phi_shapes?(instrs, then_reg, else_reg)
      end

    phi_consumes =
      cond do
        truthy_native? or native_int_phi? ->
          Builder.phi_branch_consumes(b1, [cond_reg])

        true ->
          Builder.phi_branch_consumes(b1, [cond_reg])
      end

    args =
      %{then: then_reg, else: else_reg, cond: cond_reg}
      |> maybe_put_truthy_native(truthy_native?, then_shape, else_shape, then_arm_block, else_arm_block)
      |> maybe_put_native_int_phi(
        native_int_phi?,
        int_then_shape,
        int_else_shape,
        then_arm_block,
        else_arm_block
      )

    {_, b2} =
      Builder.emit(b1, :phi, %{
        dest: merge,
        args: args,
        effects: %{
          produces: {:owned, merge},
          consumes: phi_consumes,
          borrows: [],
          fallible: false
        }
      })

    {:ok, merge, b2}
  end

  defp maybe_put_truthy_native(args, false, _, _, _, _), do: args

  defp maybe_put_truthy_native(args, true, then_shape, else_shape, then_arm_block, else_arm_block) do
    Map.merge(args, %{
      truthy_native: true,
      then_shape: then_shape,
      else_shape: else_shape,
      then_arm_block: then_arm_block,
      else_arm_block: else_arm_block
    })
  end

  defp maybe_put_native_int_phi(args, false, _, _, _, _), do: args

  defp maybe_put_native_int_phi(args, true, then_shape, else_shape, then_arm_block, else_arm_block) do
    Map.merge(args, %{
      native_int_phi: true,
      then_shape: then_shape,
      else_shape: else_shape,
      then_arm_block: then_arm_block,
      else_arm_block: else_arm_block
    })
  end

  defp builder_instrs(b) do
    (Map.get(b, :blocks, []) ++ [Map.get(b, :current_block)])
    |> Enum.flat_map(&Map.get(&1, :instrs, []))
  end

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id
end
