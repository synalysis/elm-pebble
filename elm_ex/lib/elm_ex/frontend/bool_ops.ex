defmodule ElmEx.Frontend.BoolOps do
  @moduledoc """
  Preserved `&&` / `||` from the layout parser.

  The yecc parser emits `%{op: :bool_and, ...}` and `%{op: :bool_or, ...}`.
  Downstream passes call `expand/1` to obtain nested `if` nodes matching legacy
  `build_and` / `build_or` desugaring.
  """

  @false_expr %{op: :constructor_ref, target: "False"}
  @true_expr %{op: :constructor_ref, target: "True"}

  @spec expand(term()) :: term()
  def expand(expr) when is_map(expr) do
    case expr do
      %{op: :bool_or, left: left, right: right} ->
        expand_bool_or(expand(left), expand(right))

      %{op: :bool_and, left: left, right: right} ->
        expand_bool_and(expand(left), expand(right))

      %{op: _} = map ->
        Map.new(map, fn {key, value} -> {key, expand(value)} end)

      other ->
        other
    end
  end

  def expand(expr) when is_list(expr), do: Enum.map(expr, &expand/1)
  def expand(expr), do: expr

  @spec expand_bool_or(map(), map()) :: map()
  defp expand_bool_or(left, right) do
    %{
      op: :if,
      cond: left,
      then_expr: @true_expr,
      else_expr: right
    }
  end

  @spec expand_bool_and(map(), map()) :: map()
  defp expand_bool_and(left, right) do
    %{
      op: :if,
      cond: left,
      then_expr: right,
      else_expr: @false_expr
    }
  end
end
