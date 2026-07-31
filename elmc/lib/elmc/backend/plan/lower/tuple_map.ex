defmodule Elmc.Backend.Plan.Lower.TupleMap do
  @moduledoc false

  # Specialize `Tuple.mapFirst` / `mapSecond` / `mapBoth` when the tuple operand
  # is a known `:tuple2` constructor. Rebuild via normal tuple2 lowering so
  # `(Int, Int)` stays on `tuple2_ints` (and can be SROA'd) instead of calling
  # boxed `elmc_tuple_map_*` helpers.

  alias Elmc.Backend.Plan.Types, as: Types
  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr

  @spec try_compile(Types.ir_expr(), Context.t(), Builder.t()) ::
          Types.compile_result() | :unsupported
  def try_compile(%{function: "elmc_tuple_map_first", args: [fun, %{op: :tuple2, left: left, right: right}]}, ctx, b) do
    with {:ok, mapped, b1} <- apply_mapper(fun, left, ctx, b),
         {:ok, right_reg, b2} <- Expr.compile(right, Context.for_branch_arm(ctx), b1) do
      rebuild(mapped, right_reg, int_pair_after_map?(fun, left, right), ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def try_compile(%{function: "elmc_tuple_map_second", args: [fun, %{op: :tuple2, left: left, right: right}]}, ctx, b) do
    with {:ok, left_reg, b1} <- Expr.compile(left, Context.for_branch_arm(ctx), b),
         {:ok, mapped, b2} <- apply_mapper(fun, right, ctx, b1) do
      rebuild(left_reg, mapped, int_pair_after_map?(fun, right, left), ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def try_compile(
        %{function: "elmc_tuple_map_both", args: [fun_a, fun_b, %{op: :tuple2, left: left, right: right}]},
        ctx,
        b
      ) do
    with {:ok, left_m, b1} <- apply_mapper(fun_a, left, ctx, b),
         {:ok, right_m, b2} <- apply_mapper(fun_b, right, ctx, b1) do
      ints? =
        intish_expr?(left) and intish_expr?(right) and intish_mapper?(fun_a) and
          intish_mapper?(fun_b)

      rebuild(left_m, right_m, ints?, ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def try_compile(_, _, _), do: :unsupported

  defp apply_mapper(%{op: :lambda, args: [name], body: body}, arg_expr, ctx, b)
       when is_binary(name) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, arg_reg, b1} <- Expr.compile(arg_expr, operand_ctx, b) do
      ctx1 = Context.put_local(ctx, name, arg_reg)
      b2 = Builder.bind_local(b1, name, arg_reg)
      Expr.compile(body, %{ctx1 | dest_stack: [:scratch], function_tail: false}, b2)
    else
      _ -> :unsupported
    end
  end

  defp apply_mapper(_, _, _, _), do: :unsupported

  defp rebuild(left_reg, right_reg, true, ctx, b)
       when is_integer(left_reg) and is_integer(right_reg) do
    Expr.compile_runtime_builtin(:tuple2_ints, [left_reg, right_reg], ctx, b)
  end

  defp rebuild(left_reg, right_reg, false, ctx, b)
       when is_integer(left_reg) and is_integer(right_reg) do
    Expr.compile_runtime_builtin(:tuple2, [left_reg, right_reg], ctx, b)
  end

  defp int_pair_after_map?(fun, mapped_side, other_side) do
    intish_expr?(mapped_side) and intish_expr?(other_side) and intish_mapper?(fun)
  end

  defp intish_mapper?(%{op: :lambda, args: [name], body: body}) when is_binary(name) do
    # Param refs inside the mapper are int-shaped when the mapped side is.
    intish_mapper_body?(body, name)
  end

  defp intish_mapper?(_), do: false

  defp intish_mapper_body?(%{op: :var, name: name}, name), do: true
  defp intish_mapper_body?(expr, _param), do: intish_expr?(expr) or mapper_call_intish?(expr)

  defp mapper_call_intish?(%{op: :call, name: name, args: args}) when is_list(args) do
    name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy", "max", "min"] and
      Enum.all?(args, fn
        %{op: :var} -> true
        arg -> intish_expr?(arg)
      end)
  end

  defp mapper_call_intish?(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    String.starts_with?(target, "Basics.") and
      Enum.all?(args, fn
        %{op: :var} -> true
        arg -> intish_expr?(arg)
      end)
  end

  defp mapper_call_intish?(_), do: false

  defp intish_expr?(%{op: :int_literal, value: value}) when is_integer(value), do: true

  defp intish_expr?(%{op: op})
       when op in [
              :add_const,
              :sub_const,
              :add_vars,
              :sub_vars,
              :mul_vars,
              :idiv_vars,
              :min_vars,
              :max_vars,
              :mod_vars,
              :rem_vars,
              :record_get_int,
              :c_int_expr
            ],
       do: true

  defp intish_expr?(%{op: :call, name: name, args: args}) when is_list(args) do
    name in ["__add__", "__sub__", "__mul__", "__idiv__", "modBy", "remainderBy", "max", "min"] and
      Enum.all?(args, &intish_expr?/1)
  end

  defp intish_expr?(%{op: :qualified_call, target: target, args: args})
       when is_binary(target) and is_list(args) do
    String.starts_with?(target, "Basics.") and Enum.all?(args, &intish_expr?/1)
  end

  defp intish_expr?(_), do: false
end

