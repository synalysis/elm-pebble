defmodule Elmc.Backend.Plan.Lower.List do
  @moduledoc false

  alias Elmc.Backend.Plan.Lower.Expr
  alias Elmc.Backend.Plan.{Builder, Context}

  @spec compile_literal(list(), Context.t(), Builder.t()) ::
          {:ok, non_neg_integer(), Builder.t()} | :unsupported
  def compile_literal(items, ctx, b) when is_list(items) do
    with {:ok, nil_reg, b1} <- Expr.compile_runtime_builtin(:list_nil, [], ctx, b) do
      # Cons prepends the head; fold left-to-right over source order would reverse
      # the literal. Match legacy elmc_list_from_values (and Elm) by consing last item first.
      Enum.reduce_while(Enum.reverse(items), {:ok, nil_reg, b1}, fn item, {:ok, tail_reg, b_acc} ->
        case Expr.compile(item, ctx, b_acc) do
          {:ok, head_reg, b2} ->
            case Expr.compile_runtime_builtin(:list_cons, [head_reg, tail_reg], ctx, b2) do
              {:ok, cell_reg, b3} -> {:cont, {:ok, cell_reg, b3}}
            end

          :unsupported ->
            {:halt, :unsupported}
        end
      end)
    end
  end
end
