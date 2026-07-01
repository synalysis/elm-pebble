defmodule Elmc.Backend.CCodegen.ConcatMapBodyPlan do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @max_items 8

  @type let_binding :: {String.t(), Types.ir_expr()}
  @type plan ::
          {:items, [Types.ir_expr()]}
          | {:if, Types.ir_expr(), [Types.ir_expr()], [Types.ir_expr()]}

  @spec plan(Types.ir_expr()) :: {:ok, [let_binding()], plan()} | :error
  def plan(body) when is_map(body) do
    {lets, core} = flatten_let_chain(body)

    case plan_node(core) do
      :error -> :error
      plan -> {:ok, lets, plan}
    end
  end

  def plan(_body), do: :error

  @spec flatten_let_chain(Types.ir_expr()) :: {[let_binding()], Types.ir_expr()}
  defp flatten_let_chain(%{op: :let_in, name: name, value_expr: value_expr, in_expr: in_expr}) do
    {rest, body} = flatten_let_chain(in_expr)
    {[{name, value_expr} | rest], body}
  end

  defp flatten_let_chain(body), do: {[], body}

  @spec plan_node(Types.ir_expr()) :: plan() | :error
  defp plan_node(%{op: :list_literal, items: items}) when is_list(items) and length(items) <= @max_items do
    {:items, items}
  end

  defp plan_node(%{op: :if, cond: cond, then_expr: then_expr, else_expr: else_expr}) do
    with {:items, then_items} <- plan_node(then_expr),
         {:items, else_items} <- plan_node(else_expr) do
      {:if, cond, then_items, else_items}
    else
      _ -> :error
    end
  end

  defp plan_node(_), do: :error
end
