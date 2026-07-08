defmodule Elmc.Backend.Plan.Lower.Compare do
  @moduledoc false

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.Types

  @spec compile(map(), Context.t(), Builder.t()) ::
          {:ok, Types.reg(), Builder.t()} | :unsupported
  def compile(%{op: :compare, kind: kind, left: left, right: right}, ctx, b) do
    compile(%{kind: kind, left: left, right: right}, ctx, b)
  end

  def compile(%{kind: kind, left: left, right: right}, ctx, b) do
    with {:ok, left_reg, left_owned?, b1} <- compile_operand(left, ctx, b),
         {:ok, right_reg, right_owned?, b2} <- compile_operand(right, ctx, b1) do
      {reg, b3} = Builder.fresh_reg(b2)

      consumes =
        [left_reg, right_reg]
        |> Enum.zip([left_owned?, right_owned?])
        |> Enum.flat_map(fn
          {r, true} -> [r]
          _ -> []
        end)

      {_, b4} =
        Builder.emit(b3, :compare, %{
          dest: reg,
          args: %{kind: kind || :eq, left: left_reg, right: right_reg},
          effects: %{
            produces: {:owned, reg},
            consumes: consumes,
            borrows: [left_reg, right_reg],
            fallible: false
          }
        })

      {:ok, reg, b4}
    else
      _ -> :unsupported
    end
  end

  def compile(_, _, _), do: :unsupported

  defp compile_operand(expr, ctx, b) do
    case Expr.compile(expr, ctx, b) do
      {:ok, reg, b1} -> {:ok, reg, operand_owned?(expr), b1}
      other -> other
    end
  end

  defp operand_owned?(%{op: op})
       when op in [:int_literal, :bool_literal, :string_literal, :cmd_none, :sub_none],
       do: true

  defp operand_owned?(_), do: false
end
