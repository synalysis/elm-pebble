defmodule ElmEx.Frontend.ApplyLeft do
  @moduledoc """
  Preserved `<|` application from the layout parser.

  The yecc parser emits `%{op: :apply_left, fn_expr: ..., arg: ...}`. Downstream
  passes call `expand/1` to obtain nested call nodes matching legacy `build_app/2`.
  """

  @spec expand(term()) :: term()
  def expand(expr) when is_map(expr) do
    case expr do
      %{op: :apply_left, fn_expr: fn_expr, arg: arg} ->
        expand_apply_left(expand(fn_expr), expand(arg))

      %{op: _} = map ->
        Map.new(map, fn {key, value} -> {key, expand(value)} end)

      other ->
        other
    end
  end

  def expand(expr) when is_list(expr), do: Enum.map(expr, &expand/1)
  def expand(expr), do: expr

  @spec expand_apply_left(map(), map()) :: map()
  defp expand_apply_left(fn_expr, arg) do
    case fn_expr do
      %{op: :var, name: name} ->
        %{op: :call, name: name, args: [arg]}

      %{op: :qualified_ref, target: target} ->
        %{op: :qualified_call, target: target, args: [arg]}

      %{op: :constructor_ref, target: target} ->
        %{op: :constructor_call, target: target, args: [arg]}

      %{op: :call, name: name, args: args} ->
        %{op: :call, name: name, args: args ++ [arg]}

      %{op: :qualified_call, target: target, args: args} ->
        %{op: :qualified_call, target: target, args: args ++ [arg]}

      %{op: :constructor_call, target: target, args: args} ->
        %{op: :constructor_call, target: target, args: args ++ [arg]}

      %{op: :field_access, arg: base, field: field} ->
        %{op: :field_call, arg: base, field: field, args: [arg]}

      %{op: :field_call, arg: base, field: field, args: args} ->
        %{op: :field_call, arg: base, field: field, args: args ++ [arg]}

      %{op: :compose_left, f: f, g: g} ->
        expand_expr_apply(f, expand_expr_apply(g, arg))

      %{op: :compose_right, f: f, g: g} ->
        expand_expr_apply(g, expand_expr_apply(f, arg))

      other ->
        %{op: :call, name: "__apply__", args: [other, arg]}
    end
  end

  @spec expand_expr_apply(map(), map()) :: map()
  defp expand_expr_apply(%{op: :qualified_call, target: target, args: args}, arg) do
    %{op: :qualified_call, target: target, args: args ++ [arg]}
  end

  defp expand_expr_apply(%{op: :call, name: name, args: args}, arg) do
    %{op: :call, name: name, args: args ++ [arg]}
  end

  defp expand_expr_apply(%{op: :constructor_call, target: target, args: args}, arg) do
    %{op: :constructor_call, target: target, args: args ++ [arg]}
  end

  defp expand_expr_apply(%{op: :var, name: name}, arg) do
    %{op: :call, name: name, args: [arg]}
  end

  defp expand_expr_apply(%{op: :qualified_ref, target: target}, arg) do
    %{op: :qualified_call, target: target, args: [arg]}
  end

  defp expand_expr_apply(%{op: :constructor_ref, target: target}, arg) do
    %{op: :constructor_call, target: target, args: [arg]}
  end

  defp expand_expr_apply(other, arg) do
    %{op: :call, name: "__apply__", args: [other, arg]}
  end
end
