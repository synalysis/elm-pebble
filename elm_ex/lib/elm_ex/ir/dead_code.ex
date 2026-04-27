defmodule ElmEx.IR.DeadCode do
  @moduledoc """
  Dead-code elimination for function declarations in IR.

  Keeps only functions reachable from entry module roots plus qualified calls.
  """

  alias ElmEx.IR

  @default_roots ["init", "update", "view", "subscriptions", "main"]

  @spec strip(IR.t(), String.t()) :: IR.t()
  def strip(%IR{} = ir, entry_module) do
    function_map =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl ->
          {"#{mod.name}.#{decl.name}", {mod.name, decl.name, decl.expr}}
        end)
      end)
      |> Map.new()

    initial_roots =
      @default_roots
      |> Enum.map(&"#{entry_module}.#{&1}")
      |> Enum.filter(&Map.has_key?(function_map, &1))

    reachable = walk_reachable(function_map, MapSet.new(initial_roots), initial_roots)

    modules =
      Enum.map(ir.modules, fn mod ->
        declarations =
          Enum.filter(mod.declarations, fn decl ->
            decl.kind != :function || MapSet.member?(reachable, "#{mod.name}.#{decl.name}")
          end)

        %{mod | declarations: declarations}
      end)

    %{ir | modules: modules}
  end

  @spec walk_reachable(map(), MapSet.t(), [String.t()]) :: MapSet.t()
  defp walk_reachable(_function_map, seen, []), do: seen

  defp walk_reachable(function_map, seen, [current | rest]) do
    next_calls =
      case Map.get(function_map, current) do
        {module, _name, expr} -> collect_calls(expr, module)
        _ -> []
      end
      |> Enum.filter(&Map.has_key?(function_map, &1))
      |> Enum.reject(&MapSet.member?(seen, &1))

    seen = Enum.reduce(next_calls, seen, &MapSet.put(&2, &1))
    walk_reachable(function_map, seen, rest ++ next_calls)
  end

  @spec collect_calls(map() | nil, String.t()) :: [String.t()]
  defp collect_calls(nil, _mod), do: []

  defp collect_calls(%{op: :qualified_call, target: target, args: args}, mod)
       when is_binary(target) do
    arg_calls = Enum.flat_map(args || [], &collect_calls(&1, mod))
    [target | arg_calls]
  end

  defp collect_calls(%{op: :constructor_call, args: args}, mod) when is_list(args) do
    Enum.flat_map(args, &collect_calls(&1, mod))
  end

  defp collect_calls(%{op: :qualified_call1, target: target}, _mod) when is_binary(target) do
    [target]
  end

  defp collect_calls(%{op: :tuple2, left: left, right: right}, mod) do
    collect_calls(left, mod) ++ collect_calls(right, mod)
  end

  defp collect_calls(%{op: :list_literal, items: items}, mod) when is_list(items) do
    Enum.flat_map(items, &collect_calls(&1, mod))
  end

  defp collect_calls(%{op: :call, name: name, args: args}, mod) when is_binary(name) do
    ["#{mod}.#{name}" | Enum.flat_map(args || [], &collect_calls(&1, mod))]
  end

  defp collect_calls(%{op: :call1, name: name}, mod) when is_binary(name) do
    ["#{mod}.#{name}"]
  end

  defp collect_calls(%{op: :var, name: name}, mod) when is_binary(name) do
    ["#{mod}.#{name}"]
  end

  defp collect_calls(%{op: :let_in, value_expr: value_expr, in_expr: in_expr}, mod) do
    collect_calls(value_expr, mod) ++ collect_calls(in_expr, mod)
  end

  defp collect_calls(%{op: :if, cond: cond_expr, then_expr: then_expr, else_expr: else_expr}, mod) do
    collect_calls(cond_expr, mod) ++
      collect_calls(then_expr, mod) ++ collect_calls(else_expr, mod)
  end

  defp collect_calls(%{op: :compare, left: left, right: right}, mod) do
    collect_calls(left, mod) ++ collect_calls(right, mod)
  end

  defp collect_calls(%{op: :record_literal, fields: fields}, mod) when is_list(fields) do
    Enum.flat_map(fields, fn
      %{expr: expr} -> collect_calls(expr, mod)
      _ -> []
    end)
  end

  defp collect_calls(%{op: :field_access, arg: arg}, mod) when is_map(arg) do
    collect_calls(arg, mod)
  end

  defp collect_calls(%{op: :lambda, body: body}, mod) when is_map(body) do
    collect_calls(body, mod)
  end

  defp collect_calls(%{op: :case, branches: branches}, mod) when is_list(branches) do
    Enum.flat_map(branches, fn branch -> collect_calls(branch.expr, mod) end)
  end

  defp collect_calls(_, _mod), do: []
end
