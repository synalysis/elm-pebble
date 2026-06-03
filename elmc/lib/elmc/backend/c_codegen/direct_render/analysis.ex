defmodule Elmc.Backend.CCodegen.DirectRender.Analysis do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @type target_sets_result :: Types.direct_target_sets()

  @spec entry_roots(Types.function_decl_map(), Types.codegen_opts()) :: [
          Types.function_decl_key()
        ]
  def entry_roots(decl_map, opts) do
    entry_module = opts[:entry_module] || "Main"

    entry_roots =
      ["init", "update", "subscriptions", "view", "main"]
      |> Enum.map(&{entry_module, &1})

    exported_runtime_roots =
      decl_map
      |> Map.keys()
      |> Enum.filter(fn {_module_name, decl_name} ->
        String.ends_with?(decl_name, "_commands_from")
      end)

    (entry_roots ++ exported_runtime_roots)
    |> Enum.uniq()
    |> Enum.filter(&Map.has_key?(decl_map, &1))
  end

  @spec targets(ElmEx.IR.t(), Types.codegen_opts(), Types.function_decl_map()) ::
          MapSet.t(Types.function_decl_key())
  def targets(_ir, opts, decl_map) do
    {def_targets, emit_targets, _pruned} = target_sets(decl_map, opts)
    validate_direct_render_only!(opts, decl_map, emit_targets)
    def_targets
  end

  @spec filtered_candidates(Types.function_decl_map()) :: MapSet.t(Types.function_decl_key())
  defp filtered_candidates(decl_map) do
    Enum.reduce(decl_map, MapSet.new(), fn {{module_name, decl_name}, decl}, acc ->
      if candidate_module?(module_name) and
           Host.direct_supported?(decl.expr, module_name, decl_map, MapSet.new()) do
        MapSet.put(acc, {module_name, decl_name})
      else
        acc
      end
    end)
    |> Host.filter_direct_targets(decl_map)
  end

  @spec target_sets(Types.function_decl_map(), Types.codegen_opts()) :: target_sets_result()
  def target_sets(decl_map, opts) do
    filtered = filtered_candidates(decl_map)
    affine_pruned = Host.affine_pruned_map_callback_targets(filtered, decl_map, opts)

    emit_targets =
      if opts[:strip_dead_code] == false do
        filtered
      else
        roots = direct_entry_roots(filtered, decl_map, opts)
        direct_reachable_targets(roots, filtered, decl_map, MapSet.new())
      end

    use_sites = Host.collect_direct_function_use_sites(emit_targets, decl_map)

    pruned =
      affine_pruned
      |> MapSet.union(Host.direct_single_call_prune_targets(emit_targets, use_sites, decl_map, opts))

    def_targets = MapSet.difference(emit_targets, pruned)
    {def_targets, emit_targets, pruned}
  end

  defp validate_direct_render_only!(opts, decl_map, direct_targets) do
    entry_module = opts[:entry_module] || "Main"
    entry_view = {entry_module, "view"}

    if opts[:direct_render_only] == true and Map.has_key?(decl_map, entry_view) and
         not MapSet.member?(direct_targets, entry_view) do
      raise ArgumentError,
            "direct_render_only requires #{entry_module}.view to be supported by direct Pebble command generation"
    end
  end

  @spec direct_entry_roots(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map(),
          Types.codegen_opts()
        ) :: [Types.function_decl_key()]
  defp direct_entry_roots(candidates, decl_map, opts) do
    entry_roots(decl_map, opts)
    |> Enum.filter(&MapSet.member?(candidates, &1))
  end

  defp direct_reachable_targets([], _candidates, _decl_map, seen), do: seen

  defp direct_reachable_targets([target | rest], candidates, decl_map, seen) do
    cond do
      MapSet.member?(seen, target) ->
        direct_reachable_targets(rest, candidates, decl_map, seen)

      not MapSet.member?(candidates, target) ->
        direct_reachable_targets(rest, candidates, decl_map, seen)

      true ->
        decl = Map.fetch!(decl_map, target)
        module_name = elem(target, 0)
        callees = direct_expr_callees(decl.expr, module_name, candidates, decl_map)
        direct_reachable_targets(rest ++ callees, candidates, decl_map, MapSet.put(seen, target))
    end
  end

  defp direct_expr_callees(expr, module_name, candidates, decl_map) do
    expr
    |> direct_expr_callees_list(module_name, candidates, decl_map)
    |> Enum.uniq()
  end

  defp direct_expr_callees_list(expr, module_name, candidates, decl_map) when is_map(expr) do
    own =
      case expr do
        %{op: :call, name: "__append__"} ->
          []

        %{op: :call, name: name} ->
          target = {module_name, name}
          if MapSet.member?(candidates, target), do: [target], else: []

        %{op: :qualified_call, target: target, args: args} ->
          normalized = Host.normalize_special_target(target)

          case Host.special_value_from_target(normalized, args || []) do
            nil ->
              case Host.split_qualified_function_target(normalized) do
                nil ->
                  []

                target_key ->
                  if MapSet.member?(candidates, target_key), do: [target_key], else: []
              end

            rewritten ->
              direct_expr_callees(rewritten, module_name, candidates, decl_map)
          end

        %{op: :var, name: name} ->
          target = {module_name, name}
          if MapSet.member?(candidates, target), do: [target], else: []

        _ ->
          []
      end

    child_callees =
      expr
      |> Map.values()
      |> Enum.flat_map(&direct_expr_callees_list(&1, module_name, candidates, decl_map))

    own ++ child_callees
  end

  defp direct_expr_callees_list(values, module_name, candidates, decl_map) when is_list(values) do
    Enum.flat_map(values, &direct_expr_callees_list(&1, module_name, candidates, decl_map))
  end

  defp direct_expr_callees_list(_value, _module_name, _candidates, _decl_map), do: []

  defp candidate_module?(module_name) do
    not core_library_module?(module_name) and
      not String.starts_with?(module_name, "Pebble.Ui") and
      not String.starts_with?(module_name, "Pebble.Platform") and
      not String.starts_with?(module_name, "Pebble.Events") and
      not String.starts_with?(module_name, "Pebble.Frame") and
      not String.starts_with?(module_name, "Pebble.Button") and
      not String.starts_with?(module_name, "Pebble.Storage") and
      not String.starts_with?(module_name, "Pebble.Cmd") and
      not String.starts_with?(module_name, "Elm.Kernel.")
  end

  defp core_library_module?(module_name) do
    module_name in [
      "Basics",
      "Bitwise",
      "Char",
      "Debug",
      "Dict",
      "Json.Decode",
      "Json.Encode",
      "List",
      "Maybe",
      "Platform",
      "Platform.Cmd",
      "Platform.Sub",
      "Random",
      "Result",
      "Set",
      "String",
      "Sub",
      "Tuple"
    ]
  end
end
