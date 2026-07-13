defmodule Elmc.Backend.Plan.Lower.Tuple do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec compile(Types.ir_expr(), Context.t(), Builder.t()) :: Types.compile_result_required()
  def compile(%{op: :tuple_first_expr, arg: arg}, ctx, b),
    do: compile_proj(:first, arg, ctx, b)

  def compile(%{op: :tuple_second_expr, arg: arg}, ctx, b),
    do: compile_proj(:second, arg, ctx, b)

  def compile(%{op: :tuple_first, arg: arg}, ctx, b),
    do: compile_proj(:first, arg, ctx, b)

  def compile(%{op: :tuple_second, arg: arg}, ctx, b),
    do: compile_proj(:second, arg, ctx, b)

  def compile(_, _, _), do: :unsupported

  defp compile_proj(which, arg, ctx, b) do
    with {:ok, base, b1} <- resolve_arg(arg, ctx, b) do
      {dest, b2} = dest_for(ctx, b1)

      {_, b3} =
        Builder.emit(b2, :tuple_proj, %{
          dest: dest,
          args: %{base: base, which: which},
          effects:
            if(is_integer(dest),
              do: %{
                produces: {:owned, dest},
                consumes: [],
                borrows: [base],
                fallible: false
              },
              else: Types.empty_effects()
            )
        })

      {:ok, dest, b3}
    else
      _ -> :unsupported
    end
  end

  defp resolve_arg(%{op: :var, name: name}, ctx, b) when is_binary(name) do
    case Context.local_reg(ctx, name) do
      reg when is_integer(reg) -> {:ok, reg, b}
      _ -> Expr.compile(%{op: :var, name: name}, ctx, b)
    end
  end

  defp resolve_arg(arg, ctx, b) when is_map(arg), do: Expr.compile(arg, ctx, b)
  defp resolve_arg(_, _, _), do: :unsupported

  defp dest_for(ctx, b) do
    case Context.dest_for_call(ctx) do
      :fn_out -> {:fn_out, b}
      :branch_out -> {:branch_out, b}
      :scratch -> Builder.fresh_reg(b)
    end
  end
end
