defmodule Elmc.Backend.Plan.Lower.List do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.{Builder, Context}

  @min_static_list_items 4
  @min_static_values_items 1

  @simple_literal_ops [:int_literal, :float_literal, :bool_literal, :string_literal, :char_literal]

  @spec compile_literal([Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, non_neg_integer(), Builder.t()} | :unsupported
  def compile_literal([], ctx, b) do
    Expr.compile_runtime_builtin(:list_nil, [], ctx, b)
  end

  def compile_literal(items, ctx, b) when is_list(items) do
    cond do
      match?({:ok, _}, static_int_literal_values(items)) ->
        {:ok, values} = static_int_literal_values(items)
        Expr.compile_const_static_list({:int_array, values}, ctx, b)

      length(items) >= @min_static_list_items and
          match?({:ok, _}, static_float_literal_values(items)) ->
        {:ok, values} = static_float_literal_values(items)
        Expr.compile_const_static_list({:float_array, values}, ctx, b)

      length(items) >= @min_static_list_items and
          match?({:ok, _}, static_tuple2_int_literal_values(items)) ->
        {:ok, pairs} = static_tuple2_int_literal_values(items)
        Expr.compile_const_static_list({:tuple2_int_array, pairs}, ctx, b)

      length(items) >= @min_static_values_items and
          Enum.all?(items, &primitive_record_literal?/1) ->
        compile_static_record_array(items, ctx, b)

      length(items) >= @min_static_values_items and
          Enum.all?(items, &simple_literal_item?/1) ->
        compile_static_values_array(items, ctx, b)

      length(items) >= @min_static_values_items ->
        compile_static_values_array(items, ctx, b)

      true ->
        compile_literal_cons(items, ctx, b)
    end
  end

  defp compile_static_record_array(items, ctx, b) do
    scratch = Context.for_branch_arm(ctx)

    with {:ok, regs, b1} <- compile_item_regs(items, scratch, b) do
      Expr.compile_const_static_list({:record_array, regs}, scratch, b1)
    end
  end

  defp compile_static_values_array(items, ctx, b) do
    scratch = Context.for_branch_arm(ctx)

    with {:ok, regs, b1} <- compile_item_regs(items, scratch, b) do
      Expr.compile_const_static_list({:values, regs}, scratch, b1)
    end
  end

  defp compile_item_regs(items, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(items, {:ok, [], b}, fn item, {:ok, acc, b_acc} ->
      case Expr.compile(item, operand_ctx, b_acc) do
        {:ok, reg, b1} when is_integer(reg) -> {:cont, {:ok, acc ++ [reg], b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  defp compile_literal_cons(items, ctx, b) do
    operand_ctx = Context.for_branch_arm(ctx)

    with {:ok, nil_reg, b1} <- Expr.compile_runtime_builtin(:list_nil, [], operand_ctx, b) do
      # Cons prepends the head; fold left-to-right over source order would reverse
      # the literal. Match legacy elmc_list_from_values (and Elm) by consing last item first.
      Enum.reduce_while(Enum.reverse(items), {:ok, nil_reg, b1}, fn item, {:ok, tail_reg, b_acc} ->
        case Expr.compile(item, operand_ctx, b_acc) do
          {:ok, head_reg, b2} ->
            case Expr.compile_runtime_builtin(:list_cons, [head_reg, tail_reg], operand_ctx, b2) do
              {:ok, cell_reg, b3} -> {:cont, {:ok, cell_reg, b3}}
            end

          :unsupported ->
            {:halt, :unsupported}
        end
      end)
    end
  end

  defp static_int_literal_values(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn
      %{op: :int_literal, value: value}, {:ok, acc} when is_integer(value) ->
        {:cont, {:ok, [value | acc]}}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      _ -> :error
    end
  end

  defp static_float_literal_values(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn
      %{op: :float_literal, value: value}, {:ok, acc} when is_number(value) ->
        {:cont, {:ok, [value | acc]}}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      _ -> :error
    end
  end

  defp static_tuple2_int_literal_values(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn
      %{
        op: :tuple2,
        left: %{op: :int_literal, value: left},
        right: %{op: :int_literal, value: right}
      },
      {:ok, acc}
      when is_integer(left) and is_integer(right) ->
        {:cont, {:ok, [{left, right} | acc]}}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      _ -> :error
    end
  end

  defp simple_literal_item?(%{op: op}) when op in @simple_literal_ops, do: true
  defp simple_literal_item?(_), do: false

  defp primitive_record_literal?(%{op: :record_literal, fields: fields}) when is_list(fields) do
    fields != [] and Enum.all?(fields, &primitive_record_field?/1)
  end

  defp primitive_record_literal?(%{op: :record_literal, fields: fields}) when is_map(fields) do
    map_size(fields) > 0 and Enum.all?(fields, fn {_field, expr} -> primitive_record_expr?(expr) end)
  end

  defp primitive_record_literal?(_), do: false

  defp primitive_record_field?(%{expr: expr}), do: primitive_record_expr?(expr)
  defp primitive_record_field?(_), do: false

  defp primitive_record_expr?(%{op: op}) when op in [:int_literal, :float_literal, :bool_literal, :char_literal],
    do: true

  defp primitive_record_expr?(_), do: false
end
