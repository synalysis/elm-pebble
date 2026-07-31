defmodule Elmc.Backend.Plan.Lower.ListCursor do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Lower.Lambda
  alias Elmc.Backend.Plan.{Builder, Context, Types}

  @list_range_targets ~w(List.range Elm.Kernel.List.range)

  @spec try_compile_map(Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def try_compile_map(%{function: "elmc_list_map", args: [fun, list]}, ctx, b) do
    case try_range_map(fun, list, ctx, b) do
      {:ok, _, _} = ok ->
        ok

      :unsupported ->
        case int_list_literal_range(list) do
          {:ok, start, end_val} -> try_range_literals(fun, start, end_val, ctx, b)
          :error -> :unsupported
        end
    end
  end

  def try_compile_map(_, _, _), do: :unsupported

  @spec int_list_literal_range(term()) :: {:ok, integer(), integer()} | :error
  defp int_list_literal_range(%{op: :static_list, elements: elements}) when is_list(elements) do
    values =
      elements
      |> Enum.map(&literal_int/1)
      |> Enum.reduce_while([], fn
        {:ok, value}, acc -> {:cont, acc ++ [value]}
        :error, _ -> {:halt, :error}
      end)

    case values do
      :error -> :error
      [] -> :error
      [single] -> {:ok, single, single}
      ints -> if consecutive_ints?(ints), do: {:ok, hd(ints), List.last(ints)}, else: :error
    end
  end

  defp int_list_literal_range(%{op: :list_literal, elements: elements}) when is_list(elements),
    do: int_list_literal_range(%{op: :static_list, elements: elements})

  defp int_list_literal_range(_), do: :error

  defp consecutive_ints?([_]), do: true

  defp consecutive_ints?(ints) do
    Enum.chunk_every(ints, 2, 1, :discard)
    |> Enum.all?(fn [left, right] -> right == left + 1 end)
  end

  defp try_range_map(fun, list, ctx, b) do
    with {:ok, start, end_val, {:literal, s, e}} <- parse_range(list),
         {:ok, dest, b_out} <- emit_range_map(fun, s, e, start, end_val, ctx, b) do
      {:ok, dest, b_out}
    else
      _ -> :unsupported
    end
  end

  defp try_range_literals(fun, start, end_val, ctx, b) do
    emit_range_map(fun, start, end_val, start, end_val, ctx, b)
  end

  defp emit_range_map(fun, start_reg, end_reg, _start, _end_val, ctx, b) do
    with {:ok, _lambda, _body} <- map_lambda(fun),
         {:ok, lambda_idx, _capture_regs, b1} <- Lambda.compile_for_direct_call(fun, ctx, b) do
      {dest, b2} = dest_for_call(ctx, b1)

      args = %{
        start: start_reg,
        end: end_reg,
        lambda_idx: lambda_idx,
        start_literal?: is_integer(start_reg),
        end_literal?: is_integer(end_reg)
      }

      effects =
        if is_integer(dest) do
          Types.fallible_effects(dest, [], [])
        else
          Types.fallible_transfer([], [])
        end

      wrap_catch? = Builder.wrap_fallible_instr_catch?(b2, ctx, true)
      b4 = if wrap_catch?, do: Builder.catch_begin(b2), else: b2

      {_, b5} =
        Builder.emit(b4, :list_cursor_map, %{
          dest: dest,
          args: args,
          effects: effects
        })

      b6 = if wrap_catch?, do: Builder.catch_end(b5), else: b5
      {:ok, dest, b6}
    else
      _ -> :unsupported
    end
  end

  @spec parse_range(term()) ::
          {:ok, integer(), integer(), {:literal, integer(), integer()}} | :unsupported
  defp parse_range(%{op: :qualified_call, target: target, args: [start, end_expr]})
       when target in @list_range_targets do
    case {literal_int(start), literal_int(end_expr)} do
      {{:ok, s}, {:ok, e}} -> {:ok, s, e, {:literal, s, e}}
      _ -> :unsupported
    end
  end

  defp parse_range(%{op: :runtime_call, function: "elmc_list_range", args: [start, end_expr]}) do
    case {literal_int(start), literal_int(end_expr)} do
      {{:ok, s}, {:ok, e}} -> {:ok, s, e, {:literal, s, e}}
      _ -> :unsupported
    end
  end

  defp parse_range(_), do: :unsupported

  @spec literal_int(term()) :: {:ok, integer()} | :error
  defp literal_int(%{op: :int_literal, value: v}) when is_integer(v), do: {:ok, v}
  defp literal_int(_), do: :error

  @spec map_lambda(term()) :: {:ok, String.t(), term()} | :error
  defp map_lambda(%{op: :lambda, args: [param], body: body}) when is_binary(param),
    do: {:ok, param, body}

  defp map_lambda(_), do: :error

  @spec dest_for_call(Context.t(), Builder.t()) ::
          {Types.reg() | :fn_out | :branch_out, Builder.t()}
  defp dest_for_call(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end
end
