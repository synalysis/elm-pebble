defmodule Elmc.Backend.Plan.Lower.FilterMapIdentity do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.CCodegen.ListHofResolve
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.{Builder, Context, Types}

  @nothing_names ~w(Nothing Maybe.Nothing)
  @just_names ~w(Just Maybe.Just)

  @spec try_compile(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def try_compile(%{function: "elmc_list_filter_map", args: [fun, list]}, ctx, b) do
    if ListHofResolve.filter_map_identity?(fun) do
      case list do
        %{op: :list_literal, items: items} when is_list(items) ->
          compile_literal_cat(items, ctx, b)

        _ ->
          :unsupported
      end
    else
      :unsupported
    end
  end

  def try_compile(_, _, _), do: :unsupported

  defp compile_literal_cat(items, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, nil_reg, b1} <- Expr.compile_runtime_builtin(:list_nil, [], operand_ctx, b),
         {:ok, acc_reg, b2} <- fold_literal_items(items, nil_reg, operand_ctx, b1),
         {:ok, out_reg, b3} <- Expr.compile_runtime_builtin(:list_reverse, [acc_reg], ctx, b2) do
      {:ok, out_reg, b3}
    else
      _ -> :unsupported
    end
  end

  defp fold_literal_items(items, acc_reg, ctx, b) do
    Enum.reduce_while(items, {:ok, acc_reg, b}, fn item, {:ok, acc, b_acc} ->
      case classify_item(item) do
        :skip ->
          {:cont, {:ok, acc, b_acc}}

        {:include, inner} ->
          with {:ok, value_reg, b1} <- Expr.compile(inner, ctx, b_acc),
               {:ok, acc1, b2} <- prepend_item(value_reg, acc, ctx, b1) do
            {:cont, {:ok, acc1, b2}}
          else
            _ -> {:halt, :unsupported}
          end

        {:conditional, cond_expr, inner} ->
          with {:ok, cond_reg, b1} <- Expr.compile(cond_expr, ctx, b_acc),
               {:ok, value_reg, b2} <- Expr.compile(inner, ctx, b1),
               {:ok, acc1, b3} <- prepend_if(cond_reg, value_reg, acc, ctx, b2) do
            {:cont, {:ok, acc1, b3}}
          else
            _ -> {:halt, :unsupported}
          end
      end
    end)
  end

  defp prepend_item(value_reg, acc_reg, ctx, b) do
    Expr.compile_runtime_builtin(:list_cons, [value_reg, acc_reg], ctx, b)
  end

  defp prepend_if(cond_reg, value_reg, acc_reg, ctx, b) do
    saved_pending = Map.get(b, :pending_merge_block)

    with {:ok, test_reg, b1} <- emit_test_nonzero(cond_reg, b),
         then_id = b1.next_block,
         else_id = then_id + 1,
         merge_id = skip_reserved(else_id + 1, saved_pending),
         b_entry = Builder.finish_block(b1, {:br_if, then_id, else_id, test_reg}),
         b_reserved = %{b_entry | next_block: max(b_entry.next_block, merge_id + 1)},
         {:ok, then_reg, then_exit, b_then} <-
           prepend_branch(acc_reg, value_reg, ctx, b_reserved, then_id),
         b_then_done = Builder.patch_terminator(b_then, then_exit, {:br, merge_id}),
         b_else = Builder.begin_cfg_arm_block(b_then_done, else_id),
         _else_exit = b_else.current_block.id,
         b_else_done = Builder.finish_block(b_else, {:br, merge_id}),
         b_merge = Builder.begin_block(b_else_done, merge_id),
         {:ok, merge, b_out} <- emit_merge(test_reg, then_reg, acc_reg, b_merge) do
      {:ok, merge, %{b_out | pending_merge_block: saved_pending}}
    end
  end

  defp prepend_branch(acc_reg, value_reg, ctx, b, block_id) do
    b_arm = Builder.begin_cfg_arm_block(b, block_id)
    arm_ctx = Context.for_branch_arm(ctx)

    with {:ok, reg, b1} <- prepend_item(value_reg, acc_reg, arm_ctx, b_arm) do
      exit_id = b1.current_block.id
      {:ok, reg, exit_id, Builder.finish_block(b1, :none)}
    end
  end

  defp classify_item(expr) do
    cond do
      nothing_ctor?(expr) ->
        :skip

      true ->
        case just_inner(expr) do
          {:ok, inner} ->
            {:include, inner}

          :error ->
            case conditional_maybe_item(expr) do
              {:ok, cond_expr, inner} -> {:conditional, cond_expr, inner}
              :error -> {:include, expr}
            end
        end
    end
  end

  defp conditional_maybe_item(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}) do
    cond do
      nothing_branch?(then_expr) ->
        case just_inner(else_expr) do
          {:ok, inner} -> {:ok, cond, inner}
          _ -> :error
        end

      nothing_branch?(else_expr) ->
        case just_inner(then_expr) do
          {:ok, inner} -> {:ok, cond, inner}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp conditional_maybe_item(_), do: :error

  defp nothing_ctor?(%{op: :constructor_call, target: target, args: args}) when is_list(args) do
    short_name(target) in @nothing_names and args == []
  end

  defp nothing_ctor?(%{op: :int_literal, value: 0}), do: true
  defp nothing_ctor?(_), do: false

  defp just_inner(%{op: :constructor_call, target: target, args: [inner]})
       when is_binary(target),
       do: if(short_name(target) in @just_names, do: {:ok, inner}, else: :error)

  defp just_inner(%{op: :tuple2, left: %{op: :int_literal, value: 1}, right: inner}), do: {:ok, inner}
  defp just_inner(_), do: :error

  defp nothing_branch?(expr), do: nothing_ctor?(expr)

  defp short_name(target) when is_binary(target) do
    target |> String.split(".") |> List.last()
  end

  defp emit_test_nonzero(cond_reg, b) do
    {zero, b0} = Builder.emit_const_int(b, 0)
    {reg, b1} = Builder.fresh_reg(b0)

    {_, b2} =
      Builder.emit(b1, :compare, %{
        dest: reg,
        args: %{kind: :neq, left: cond_reg, right: zero},
        effects: %{
          produces: {:owned, reg},
          consumes: [],
          borrows: [cond_reg, zero],
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
