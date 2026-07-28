defmodule Elmc.Backend.Plan.Lower.Stream.List do
  @moduledoc false
  alias Elmc.Backend.Plan.Types, as: Types

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Expr

  @spec compile([Types.ir_expr()], Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def compile([], _ctx, b), do: {:ok, :stream_void, b}

  def compile(items, ctx, b) when is_list(items) do
    arm_ctx = Context.for_branch_arm(ctx)

    Enum.reduce_while(items, {:ok, :stream_void, b}, fn item, {:ok, :stream_void, b_acc} ->
      case Expr.compile(item, arm_ctx, b_acc) do
        {:ok, :stream_void, b1} -> {:cont, {:ok, :stream_void, b1}}
        _ -> {:halt, :unsupported}
      end
    end)
  end

  @spec compile_append(Types.ir_expr(), Types.ir_expr(), Context.t(), Builder.t()) ::
          {:ok, :stream_void, Builder.t()} | :unsupported
  def compile_append(left, right, ctx, b) do
    with {:ok, :stream_void, b1} <- compile_expr(left, ctx, b),
         {:ok, :stream_void, b2} <- compile_expr(right, ctx, b1) do
      {:ok, :stream_void, b2}
    else
      _ -> :unsupported
    end
  end

  defp compile_expr(expr, ctx, b) do
    case expr do
      %{op: :list_literal, items: items} -> compile(items, ctx, b)
      _ -> Expr.compile(expr, ctx, b)
    end
  end
end
