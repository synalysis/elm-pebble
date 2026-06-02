defmodule ElmEx.IR.DeadCode do
  @moduledoc """
  Dead-code elimination for function declarations in IR.

  Keeps only functions reachable from entry module roots plus qualified calls.
  """

  alias ElmEx.IR

  @default_roots ["init", "update", "view", "subscriptions", "main"]

  @doc """
  Returns `Module.function` keys reachable from `entry_module` roots (same walk as `strip/3`).
  """
  @spec reachable_keys(IR.t(), String.t(), keyword()) :: MapSet.t()
  def reachable_keys(%IR{} = ir, entry_module, opts \\ []) when is_binary(entry_module) do
    roots = Keyword.get(opts, :roots, @default_roots)
    function_map = function_map(ir)

    initial_roots =
      roots
      |> Enum.map(&"#{entry_module}.#{&1}")
      |> Enum.filter(&Map.has_key?(function_map, &1))

    walk_reachable(function_map, MapSet.new(initial_roots), initial_roots)
  end

  @spec strip(IR.t(), String.t(), keyword()) :: IR.t()
  def strip(%IR{} = ir, entry_module, opts \\ []) do
    reachable = reachable_keys(ir, entry_module, opts)

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

  @spec function_map(IR.t()) :: map()
  defp function_map(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl ->
        {"#{mod.name}.#{decl.name}", {mod.name, decl.name, decl.expr}}
      end)
    end)
    |> Map.new()
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

  defp collect_calls(%{} = expr, mod) do
    call_reference_targets(expr, mod) ++ collect_calls_from_children(expr, mod)
  end

  @spec call_reference_targets(map(), String.t()) :: [String.t()]
  defp call_reference_targets(%{op: :qualified_call, target: target}, _mod)
       when is_binary(target),
       do: [target]

  defp call_reference_targets(%{op: :qualified_call1, target: target}, _mod)
       when is_binary(target),
       do: [target]

  defp call_reference_targets(%{op: :call, name: name}, mod) when is_binary(name) do
    [local_call_target(name, mod)]
  end

  defp call_reference_targets(%{op: :call1, name: name}, mod) when is_binary(name) do
    [local_call_target(name, mod)]
  end

  defp call_reference_targets(%{op: :var, name: name}, mod) when is_binary(name) do
    [local_call_target(name, mod)]
  end

  defp call_reference_targets(_expr, _mod), do: []

  @spec local_call_target(String.t(), String.t()) :: String.t()
  defp local_call_target(name, mod) do
    if String.contains?(name, ".") do
      name
    else
      "#{mod}.#{name}"
    end
  end

  @spec collect_calls_from_children(map(), String.t()) :: [String.t()]
  defp collect_calls_from_children(expr, mod) when is_map(expr) do
    Enum.flat_map(expr, fn
      {_key, child} when is_map(child) ->
        collect_calls(child, mod)

      {_key, children} when is_list(children) ->
        Enum.flat_map(children, fn
          child when is_map(child) -> collect_calls(child, mod)
          _ -> []
        end)

      _ ->
        []
    end)
  end
end
