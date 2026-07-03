defmodule Elmc.Backend.CCodegen.AppendSegments do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @spec collect(Types.ir_expr()) :: {:ok, [Types.ir_expr()]} | :error
  def collect(expr) do
    case unwrap(expr) do
      {:append, left, right} ->
        with {:ok, left_segments} <- collect(left),
             {:ok, right_segments} <- collect(right) do
          {:ok, left_segments ++ right_segments}
        end

      {:leaf, leaf} ->
        {:ok, [leaf]}
    end
  end

  @spec unwrap(Types.ir_expr()) :: {:append, Types.ir_expr(), Types.ir_expr()} | {:leaf, Types.ir_expr()}
  defp unwrap(%{op: :runtime_call, function: "elmc_append", args: [left, right]}),
    do: {:append, left, right}

  defp unwrap(%{op: :call, name: "__append__", args: [left, right]}),
    do: {:append, left, right}

  defp unwrap(expr), do: {:leaf, expr}
end
