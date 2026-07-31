defmodule ElmEx.Frontend.Pretty.AstNormalize do
  @moduledoc false

  alias ElmEx.Frontend.{ApplyLeft, BoolOps, LetBindings}

  @doc """
  Returns true when two expression ASTs are equivalent for formatter round-trip.

  Strips layout-only metadata and compares the normalized trees structurally.
  """
  @spec equivalent?(term(), term()) :: boolean()
  def equivalent?(left, right), do: normalize(left) == normalize(right)

  @doc """
  Canonicalize parser AST for structural comparison.

  - Expands preserved sugar (`let_bindings`, `bool_and`/`bool_or`, `apply_left`)
  - Collapses synthetic `caseSubject` lets
  - Normalizes `add_vars` / `add_const` / `sub_const` to call form
  - Drops layout-only keys such as `:layout` on `let_bindings`
  """
  @spec normalize(term()) :: term()
  def normalize(expr) when is_map(expr) do
    expr
    |> collapse_case_subject()
    |> expand_preserving_forms()
    |> normalize_node()
  end

  def normalize(expr) when is_list(expr), do: Enum.map(expr, &normalize/1)
  def normalize(expr), do: expr

  @spec collapse_case_subject(map()) :: map()
  defp collapse_case_subject(%{
         op: :let_in,
         name: "caseSubject",
         value_expr: value,
         in_expr: %{op: :case, subject: "caseSubject"} = case_expr
       }) do
    Map.put(case_expr, :subject, value)
  end

  defp collapse_case_subject(expr), do: expr

  @spec expand_preserving_forms(map()) :: map()
  defp expand_preserving_forms(expr) do
    expr
    |> LetBindings.expand()
    |> BoolOps.expand()
    |> ApplyLeft.expand()
  end

  @spec normalize_node(map()) :: map()
  defp normalize_node(%{op: :add_vars, left: left, right: right}) do
    %{
      op: :call,
      name: "__add__",
      args: [%{op: :var, name: left}, %{op: :var, name: right}]
    }
  end

  defp normalize_node(%{op: :add_const, var: var, value: value}) do
    %{
      op: :call,
      name: "__add__",
      args: [%{op: :var, name: var}, %{op: :int_literal, value: value}]
    }
  end

  defp normalize_node(%{op: :sub_const, var: var, value: value}) do
    %{
      op: :call,
      name: "__sub__",
      args: [%{op: :var, name: var}, %{op: :int_literal, value: value}]
    }
  end

  defp normalize_node(%{op: :tuple_first_expr, arg: arg}) do
    normalize(%{op: :qualified_call, target: "Tuple.first", args: [arg]})
  end

  defp normalize_node(%{op: :tuple_second_expr, arg: arg}) do
    normalize(%{op: :qualified_call, target: "Tuple.second", args: [arg]})
  end

  defp normalize_node(%{op: :string_length_expr, arg: arg}) do
    normalize(%{op: :qualified_call, target: "String.length", args: [arg]})
  end

  defp normalize_node(%{op: :char_from_code_expr, arg: arg}) do
    normalize(%{op: :qualified_call, target: "Char.fromCode", args: [arg]})
  end

  defp normalize_node(%{op: :let_bindings} = expr) do
    expr
    |> Map.drop([:layout])
    |> Map.new(fn {key, value} -> {key, normalize(value)} end)
  end

  defp normalize_node(%{op: _} = expr) do
    Map.new(expr, fn {key, value} -> {key, normalize(value)} end)
  end

  defp normalize_node(expr) when is_map(expr) do
    Map.new(expr, fn {key, value} -> {key, normalize(value)} end)
  end
end
