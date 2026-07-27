defmodule ElmEx.Frontend.LetBindings do
  @moduledoc """
  Preserved multiline `let` binding lists from the layout parser.

  The yecc parser emits `%{op: :let_bindings, bindings: [...], in_expr: ...}` so
  tuple/pattern/function binding shape survives for pretty-printing. Downstream
  passes call `expand/1` to obtain nested `let_in` chains when needed.
  """
  alias ElmEx.Frontend.AstContract.Types, as: Types


  @spec expand(term()) :: term()
  def expand(expr) when is_map(expr) do
    case expr do
      %{op: :let_bindings, bindings: bindings, in_expr: in_expr} when is_list(bindings) ->
        expand_bindings(bindings, expand(in_expr))

      map ->
        # Recurse into every map value — case branches (`%{pattern, expr}`),
        # patterns, and other non-`:op` nodes — so nested `let` lists inside
        # branches (Scene3d.toWebGLEntities) are fully desugared.
        Map.new(map, fn {key, value} -> {key, expand(value)} end)
    end
  end

  def expand(expr) when is_list(expr), do: Enum.map(expr, &expand/1)
  def expand(expr), do: expr

  @spec expand_bindings([map()], map()) :: map()
  defp expand_bindings([], in_expr), do: in_expr

  defp expand_bindings([%{kind: :pattern} = binding | rest], in_expr) do
    expand_pattern_binding(binding, expand_bindings(rest, in_expr))
  end

  defp expand_bindings([binding | rest], in_expr) do
    expand_simple_binding(binding, expand_bindings(rest, in_expr))
  end


  @spec expand_simple_binding(map(), Types.expr()) :: Types.expr()

  defp expand_simple_binding(%{kind: :name, name: name, value: value}, in_expr) do
    %{op: :let_in, name: name, value_expr: expand(value), in_expr: in_expr}
  end

  defp expand_simple_binding(%{kind: :discard, value: value}, in_expr) do
    %{op: :let_in, name: "_", value_expr: expand(value), in_expr: in_expr}
  end

  defp expand_simple_binding(%{kind: :tuple2, names: names, value: value}, in_expr) do
    expand_tuple_bind(names, expand(value), in_expr)
  end

  defp expand_simple_binding(%{kind: :tuple3, names: names, value: value}, in_expr) do
    expand_tuple_bind(names, expand(value), in_expr)
  end


  @spec expand_pattern_binding(map(), Types.expr()) :: Types.expr()

  defp expand_pattern_binding(%{pattern: pattern, value: value}, in_expr) do
    tmp = pattern_bind_name(pattern)

    case_expr = %{
      op: :case,
      subject: %{op: :var, name: tmp},
      branches: [%{pattern: pattern, expr: in_expr}]
    }

    %{op: :let_in, name: tmp, value_expr: expand(value), in_expr: case_expr}
  end

  @spec expand_tuple_bind(String.t(), integer(), Types.expr()) :: Types.expr()

  defp expand_tuple_bind(names, value, in_expr) do
    tmp = tuple_bind_name(names)
    tmp_var = %{op: :var, name: tmp}
    projections = tuple_projections(tmp_var, names)

    names
    |> Enum.zip(projections)
    |> Enum.reverse()
    |> Enum.reduce(in_expr, fn {name, proj}, acc ->
      %{op: :let_in, name: name, value_expr: proj, in_expr: acc}
    end)
    |> then(&%{op: :let_in, name: tmp, value_expr: value, in_expr: &1})
  end

  @spec tuple_projections(Types.expr(), term()) :: Types.expr()

  defp tuple_projections(tmp_var, [_left, _right]) do
    [tuple_call("Tuple.first", tmp_var), tuple_call("Tuple.second", tmp_var)]
  end

  defp tuple_projections(tmp_var, [_left, _middle, _right]) do
    tail = tuple_call("Tuple.second", tmp_var)

    [
      tuple_call("Tuple.first", tmp_var),
      tuple_call("Tuple.first", tail),
      tuple_call("Tuple.second", tail)
    ]
  end

  @spec tuple_call(String.t(), Types.expr()) :: Types.expr()

  defp tuple_call(target, arg), do: %{op: :qualified_call, target: target, args: [arg]}

  @spec tuple_bind_name([String.t()]) :: String.t()
  defp tuple_bind_name(names), do: "__tupleBind_" <> Enum.join(names, "_")

  @spec pattern_bind_name(map()) :: String.t()
  defp pattern_bind_name(pattern), do: "__patternBind_" <> Integer.to_string(:erlang.phash2(pattern))
end
