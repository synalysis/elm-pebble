defmodule Elmc.Backend.Plan.Lower.MaybeAndThen do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.{Expr, MaybeMap, MaybePayload, Record}
  alias Elmc.Backend.Plan.Types

  @spec try_compile(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def try_compile(%{function: "elmc_maybe_and_then", args: [fun, maybe]}, ctx, b) do
    case MaybeMap.field_accessor_lambda(fun) do
      {:ok, field} ->
        compile_field_and_then(field, maybe, ctx, b)

      :error ->
        :unsupported
    end
  end

  def try_compile(_, _, _), do: :unsupported

  defp compile_field_and_then(field, maybe, ctx, b) when is_binary(field) do
    maybe_ctx = Context.for_branch_arm(ctx)
    payload_ctx = MaybePayload.ctx_for_payload(maybe, maybe_ctx)

    with {:ok, maybe_reg, b1} <- Expr.compile(maybe, maybe_ctx, b) do
      compile_maybe_branch_and_then(
        maybe_reg,
        fn payload_reg, arm_ctx, b_arm ->
          compile_record_field_and_then(payload_reg, field, arm_ctx, b_arm)
        end,
        payload_ctx,
        b1
      )
    else
      _ -> :unsupported
    end
  end

  defp compile_maybe_branch_and_then(maybe_reg, just_mapper, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)

    with {:ok, cond_reg, b2} <- emit_test_maybe_nothing(maybe_reg, b),
         then_id = b2.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b2, {:br_if, then_id, else_id, cond_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, then_reg, then_exit, b_then} <- compile_nothing_result(ctx, b_reserved, then_id),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         b_else_start = Builder.begin_cfg_arm_block(b_then_done, else_id),
         b_else_pending = %{b_else_start | pending_merge_block: merge_id},
         arm_ctx = Context.for_branch_arm(ctx),
         {:ok, payload_reg, b_payload} <-
           Expr.compile_runtime_builtin(:maybe_just_payload, [maybe_reg], arm_ctx, b_else_pending),
         {:ok, else_reg, else_exit, b_else} <-
           just_mapper.(payload_reg, arm_ctx, b_payload),
         b_else_done = Builder.patch_terminator(b_else, else_exit, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <- emit_merge(cond_reg, then_reg, else_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    else
      _ -> :unsupported
    end
  end

  defp compile_record_field_and_then(payload_reg, field, ctx, b) when is_integer(payload_reg) do
    with {:ok, field_reg, b1} <- compile_record_get(payload_reg, field, ctx, b) do
      exit_id = b1.current_block.id
      {:ok, field_reg, exit_id, Builder.finish_block(b1, :none)}
    end
  end

  defp compile_record_get(base_reg, field, ctx, b) when is_integer(base_reg) do
    {reg, b1} = Builder.fresh_reg(b)
    base_expr = MaybePayload.payload_base_expr(ctx)
    field_index = Record.field_index_for(field, ctx, base_expr)
    int_field? = Record.int_field?(field)
    op = if int_field?, do: :record_get_int, else: :record_get

    {_, b2} =
      Builder.emit(b1, op, %{
        dest: reg,
        args: %{base: base_reg, field: field, field_index: field_index},
        effects: %{produces: {:owned, reg}, consumes: [], borrows: [base_reg], fallible: false}
      })

    {:ok, reg, b2}
  end

  defp compile_nothing_result(ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    with {dest, b1} <- dest_for_result(arm_ctx, b_arm),
         {_, b2} <-
           Builder.emit(b1, :call_runtime, %{
             dest: dest,
             args: %{builtin: :maybe_nothing, args: []},
             effects: Types.owned_effects(dest)
           }) do
      exit_id = b2.current_block.id
      {:ok, dest, exit_id, Builder.finish_block(b2, :none)}
    else
      _ -> :unsupported
    end
  end

  defp dest_for_result(_ctx, b), do: Builder.fresh_reg(b)

  defp emit_test_maybe_nothing(subject_reg, b) do
    {reg, b1} = Builder.fresh_reg(b)

    {_, b2} =
      Builder.emit(b1, :test_maybe_nothing, %{
        dest: reg,
        args: %{reg: subject_reg},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [subject_reg],
          fallible: false
        }
      })

    {:ok, reg, b2}
  end

  defp emit_merge(cond_reg, then_reg, else_reg, b) do
    {merge, b1} = Builder.fresh_reg(b)
    phi_consumes = Builder.phi_branch_consumes(b, [then_reg, else_reg, cond_reg])

    {_, b2} =
      Builder.emit(b1, :phi, %{
        dest: merge,
        args: %{then: then_reg, else: else_reg, cond: cond_reg},
        effects: %{
          produces: {:owned, merge},
          consumes: phi_consumes,
          borrows: [],
          fallible: false
        }
      })

    {:ok, merge, b2}
  end

  defp skip_reserved(id, nil), do: id
  defp skip_reserved(id, reserved) when id == reserved, do: id + 1
  defp skip_reserved(id, _), do: id
end
