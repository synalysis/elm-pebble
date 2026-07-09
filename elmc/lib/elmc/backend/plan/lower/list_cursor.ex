defmodule Elmc.Backend.Plan.Lower.ListCursor do
  @moduledoc false

  alias Elmc.Backend.Plan.Lower.Lambda
  alias Elmc.Backend.Plan.{Builder, Context, Types}

  @list_range_targets ~w(List.range Elm.Kernel.List.range)

  @spec try_compile_map(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg() | :fn_out, Builder.t()} | :unsupported
  def try_compile_map(%{function: "elmc_list_map", args: [fun, list]}, ctx, b) do
    with {:ok, _start, _end_val, range_regs} <- parse_range(list),
         {:ok, _lambda, _body} <- map_lambda(fun),
         {:ok, lambda_idx, b1} <- compile_loop_lambda(fun, ctx, b) do
      {dest, b2} = dest_for_call(ctx, b1)

      {start_reg, end_reg, b3} =
        case range_regs do
          {:literal, s, e} ->
            {s, e, b2}
        end

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

      wrap_catch? = Builder.wrap_fallible_instr_catch?(b3, ctx, true)
      b4 = if wrap_catch?, do: Builder.catch_begin(b3), else: b3

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

  def try_compile_map(_, _, _), do: :unsupported

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

  defp literal_int(%{op: :int_literal, value: v}) when is_integer(v), do: {:ok, v}
  defp literal_int(_), do: :error

  defp map_lambda(%{op: :lambda, args: [param], body: body}) when is_binary(param),
    do: {:ok, param, body}

  defp map_lambda(_), do: :error

  defp compile_loop_lambda(fun, ctx, b) do
    case Lambda.compile(fun, ctx, b) do
      {:ok, _reg, b1} ->
        idx = max(length(b1.lambdas) - 1, 0)
        {:ok, idx, b1}

      _ ->
        :unsupported
    end
  end

  defp dest_for_call(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end
end
