defmodule Elmc.Backend.Plan.Lower.ListRecord do
  @moduledoc false

  alias Elmc.Backend.Plan.Lower.{Expr, Record}
  alias Elmc.Backend.Plan.{Builder, Context, Types}

  @spec try_compile_filter(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def try_compile_filter(%{function: "elmc_list_filter", args: [pred, list]}, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, list_reg, b1} <- Expr.compile(list, operand_ctx, b),
         {:ok, builtin, field_regs, b2} <- filter_builtin(pred, ctx, b1) do
      emit_builtin(builtin, [list_reg | field_regs], ctx, b2)
    else
      _ -> :unsupported
    end
  end

  def try_compile_filter(_, _, _), do: :unsupported

  @spec try_compile_map(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def try_compile_map(%{function: "elmc_list_map", args: [fun, list]}, ctx, b) do
    with {:ok, field} <- field_accessor_lambda(fun),
         {:ok, index_reg, b0} <- field_index_reg(field, ctx, b),
         operand_ctx = Context.for_branch_arm(ctx),
         {:ok, list_reg, b1} <- Expr.compile(list, operand_ctx, b0) do
      emit_builtin(:list_map_record_field, [list_reg, index_reg], ctx, b1)
    else
      _ -> :unsupported
    end
  end

  def try_compile_map(_, _, _), do: :unsupported

  defp filter_builtin(pred, ctx, b) do
    case parse_filter_pred(pred) do
      {:ok, :and, f1, f2} ->
        with {:ok, i1, b1} <- field_index_reg(f1, ctx, b),
             {:ok, i2, b2} <- field_index_reg(f2, ctx, b1) do
          {:ok, :list_filter_record_and, [i1, i2], b2}
        end

      {:ok, :field, field} ->
        with {:ok, index_reg, b1} <- field_index_reg(field, ctx, b) do
          {:ok, :list_filter_record_field, [index_reg], b1}
        end

      :error ->
        :unsupported
    end
  end

  defp parse_filter_pred(%{op: :lambda, args: [arg], body: body}) when is_binary(arg) do
    body = normalize_bool_predicate_body(body)

    case body do
      %{
        op: :and,
        left: %{op: :field_access, arg: left_arg, field: f1},
        right: %{op: :field_access, arg: right_arg, field: f2}
      } ->
        if var_name(left_arg) == arg and var_name(right_arg) == arg do
          {:ok, :and, f1, f2}
        else
          :error
        end

      %{
        op: :if,
        cond: left,
        then_expr: right,
        else_expr: else_expr
      } ->
        if false_branch?(else_expr) do
          with {:ok, f1} <- field_on_lambda_arg(left, arg),
               {:ok, f2} <- field_on_lambda_arg(right, arg) do
            {:ok, :and, f1, f2}
          end
        else
          :error
        end

      %{op: :call, name: name, args: [left, right]} when name in ["&&", "Basics.and", "and"] ->
        with {:ok, f1} <- field_on_lambda_arg(left, arg),
             {:ok, f2} <- field_on_lambda_arg(right, arg) do
          {:ok, :and, f1, f2}
        end

      %{op: :field_access, arg: left_arg, field: field} ->
        if var_name(left_arg) == arg, do: {:ok, :field, field}, else: :error

      _ ->
        :error
    end
  end

  defp parse_filter_pred(_), do: :error

  defp normalize_bool_predicate_body(%{op: :call, name: op, args: [left, right]})
       when op in ["&&", "Basics.and", "and"] do
    %{
      op: :if,
      cond: left,
      then_expr: right,
      else_expr: %{op: :bool_literal, value: false}
    }
  end

  defp normalize_bool_predicate_body(body), do: body

  defp false_branch?(%{op: :bool_literal, value: false}), do: true
  defp false_branch?(%{op: :int_literal, value: 0}), do: true

  defp false_branch?(%{op: :constructor_call, target: target, args: []})
       when target in ["False", "Basics.False"],
       do: true

  defp false_branch?(_expr), do: false

  defp field_on_lambda_arg(%{op: :field_access, arg: arg_name, field: field}, arg)
       when is_binary(field) and arg_name == arg,
       do: {:ok, field}

  defp field_on_lambda_arg(%{op: :field_access, arg: %{op: :var, name: arg_name}, field: field}, arg)
       when is_binary(field) and arg_name == arg,
       do: {:ok, field}

  defp field_on_lambda_arg(_expr, _arg), do: :error

  defp field_accessor_lambda(%{op: :lambda, args: [arg], body: %{op: :field_access, arg: arg_name, field: field}})
       when is_binary(arg) and is_binary(field) and arg == arg_name,
       do: {:ok, field}

  defp field_accessor_lambda(%{
         op: :lambda,
         args: [arg],
         body: %{op: :field_access, arg: %{op: :var, name: arg_name}, field: field}
       })
       when is_binary(arg) and is_binary(field) and arg == arg_name,
       do: {:ok, field}

  defp field_accessor_lambda(_), do: :error

  defp var_name(name) when is_binary(name), do: name
  defp var_name(%{op: :var, name: name}) when is_binary(name), do: name
  defp var_name(_), do: nil

  defp field_index_reg(field, ctx, b) when is_binary(field) do
    case Record.resolve_field_index_int(field, ctx) do
      {:ok, index} ->
        {reg, b1} = Builder.emit_const_int(b, index)
        {:ok, reg, b1}

      :error ->
        :unsupported
    end
  end

  defp emit_builtin(builtin, arg_regs, ctx, b) do
    wrap_catch? = Builder.wrap_fallible_instr_catch?(b, ctx, true)
    b1 = if wrap_catch?, do: Builder.catch_begin(b), else: b
    {dest, b2} = dest_for_call(ctx, b1)

    effects =
      if is_integer(dest) do
        Types.fallible_effects(dest, arg_regs, [])
      else
        Types.fallible_transfer([], [])
      end

    {_, b3} =
      Builder.emit(b2, :call_runtime, %{
        dest: dest,
        args: %{builtin: builtin, args: arg_regs},
        effects: effects
      })

    b4 = if wrap_catch?, do: Builder.catch_end(b3), else: b3
    result = if is_integer(dest), do: dest, else: dest
    {:ok, result, b4}
  end

  defp dest_for_call(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end
end
