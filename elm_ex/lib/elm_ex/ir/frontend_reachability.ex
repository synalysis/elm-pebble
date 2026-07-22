defmodule ElmEx.IR.FrontendReachability do
  @moduledoc """
  Walks frontend AST to find functions reachable from entry roots **before**
  expensive IR `rewrite_expr/2`. Used to skip lowering dead declarations.
  """

  alias ElmEx.Frontend.{ApplyLeft, BoolOps, LetBindings, Project}
  alias ElmEx.IR.ImportResolution
  alias ElmEx.IR.Lowerer

  @default_roots ["init", "update", "view", "subscriptions", "main"]

  @type function_key :: String.t()

  @doc """
  Returns `Module.name` keys reachable from `entry_module` roots, resolving
  import aliases on frontend expressions.
  """
  @spec reachable_function_keys(Project.t(), String.t(), keyword()) :: MapSet.t(function_key())
  def reachable_function_keys(%Project{} = project, entry_module, opts \\ [])
      when is_binary(entry_module) do
    roots = Keyword.get(opts, :roots, @default_roots)
    {function_map, lookups} = index_project(project)

    initial =
      roots
      |> Enum.map(&"#{entry_module}.#{&1}")
      |> Enum.filter(&Map.has_key?(function_map, &1))

    walk(function_map, lookups, MapSet.new(initial), initial)
  end

  defp index_project(%Project{modules: modules}) do
    exports = Lowerer.project_module_exports(modules)

    Enum.reduce(modules, {%{}, %{}}, fn mod, {fun_acc, lookup_acc} ->
      defs =
        mod.declarations
        |> Enum.filter(&(&1.kind == :function_definition))
        |> Map.new(&{&1.name, &1})

      local_names = MapSet.new(Map.keys(defs))

      {alias_map, alias_member_map, import_unqualified_map, _wild, type_unqualified_map} =
        Lowerer.import_resolution_for(mod, exports)

      lookup = %{
        alias_map: alias_map,
        alias_member_map: alias_member_map,
        import_unqualified_map: import_unqualified_map,
        type_unqualified_map: type_unqualified_map,
        local_call_names: local_names,
        current_module: mod.name
      }

      fun_acc =
        Enum.reduce(defs, fun_acc, fn {name, defn}, acc ->
          Map.put(acc, "#{mod.name}.#{name}", defn)
        end)

      {fun_acc, Map.put(lookup_acc, mod.name, lookup)}
    end)
  end

  defp walk(_function_map, _lookups, seen, []), do: seen

  defp walk(function_map, lookups, seen, [current | rest]) do
    next =
      case Map.get(function_map, current) do
        %{expr: expr} when is_map(expr) ->
          mod = module_of_key(current)
          lookup = Map.get(lookups, mod, %{current_module: mod, local_call_names: MapSet.new()})

          expr
          |> normalize_expr()
          |> collect_calls(lookup)
          |> Enum.filter(&Map.has_key?(function_map, &1))
          |> Enum.reject(&MapSet.member?(seen, &1))

        _ ->
          []
      end

    seen = Enum.reduce(next, seen, &MapSet.put(&2, &1))
    walk(function_map, lookups, seen, rest ++ next)
  end

  defp module_of_key(key) when is_binary(key) do
    case String.split(key, ".") do
      parts when length(parts) >= 2 ->
        parts |> Enum.drop(-1) |> Enum.join(".")

      _ ->
        key
    end
  end

  defp normalize_expr(expr) when is_map(expr) do
    expr
    |> LetBindings.expand()
    |> ApplyLeft.expand()
    |> BoolOps.expand()
  end

  defp collect_calls(nil, _lookup), do: []

  defp collect_calls(expr, lookup) when is_map(expr) do
    call_targets(expr, lookup) ++
      Enum.flat_map(expr, fn
        {_k, child} when is_map(child) -> collect_calls(child, lookup)
        {_k, list} when is_list(list) -> Enum.flat_map(list, &collect_calls_item(&1, lookup))
        _ -> []
      end)
  end

  defp collect_calls_item(item, lookup) when is_map(item), do: collect_calls(item, lookup)
  defp collect_calls_item(_, _), do: []

  defp call_targets(%{op: :qualified_call, target: target}, lookup) when is_binary(target) do
    [ImportResolution.resolve(target, lookup)]
  end

  defp call_targets(%{op: :qualified_call1, target: target}, lookup) when is_binary(target) do
    [ImportResolution.resolve(target, lookup)]
  end

  defp call_targets(%{op: :qualified_ref, target: target}, lookup) when is_binary(target) do
    if String.contains?(target, ".") do
      [ImportResolution.resolve(target, lookup)]
    else
      []
    end
  end

  defp call_targets(%{op: :call, name: name}, lookup) when is_binary(name) do
    [ImportResolution.resolve(name, lookup)]
  end

  defp call_targets(%{op: :call1, name: name}, lookup) when is_binary(name) do
    [ImportResolution.resolve(name, lookup)]
  end

  defp call_targets(%{op: :var, name: name}, lookup) when is_binary(name) do
    local? = MapSet.member?(Map.get(lookup, :local_call_names, MapSet.new()), name)
    resolved = ImportResolution.resolve(name, lookup)

    cond do
      local? ->
        [resolved]

      # Unqualified imports (exposing) resolve to Module.name even when not local.
      resolved != name and String.contains?(resolved, ".") ->
        [resolved]

      true ->
        []
    end
  end

  # `Theme.white` often parses as field_access on an import-alias module var.
  # Match ImportResolution.normalize_expr so reachable-only keeps those bindings.
  defp call_targets(%{op: :field_access, arg: arg, field: field}, lookup)
       when is_binary(field) do
    case ImportResolution.resolve_imported_member(arg, field, lookup) do
      {:ok, target} -> [target]
      :error -> []
    end
  end

  defp call_targets(%{op: :pipe_chain, base: base, steps: steps}, lookup) do
    collect_calls(base, lookup) ++
      Enum.flat_map(steps || [], &collect_calls(&1, lookup))
  end

  defp call_targets(_, _), do: []
end
