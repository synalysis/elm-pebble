defmodule Elmc.Backend.CCodegen.DirectRender.GenericTargets do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Analysis
  alias Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.GenericReachability
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Types

  @type target_set :: Types.function_target_set()

  @platform_wrapper_entries ~w(init update subscriptions main view)

  @stream_view_ui_helpers [
    {"Pebble.Ui", "toUiNode"},
    {"Pebble.Ui", "windowStack"},
    {"Pebble.Ui", "window"},
    {"Pebble.Ui", "canvasLayer"}
  ]

  @spec prune_generic_view?(Types.codegen_opts(), Types.function_decl_map(), target_set()) ::
          boolean()
  def prune_generic_view?(opts, decl_map, direct_targets) do
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    opts[:stream_view_fallback] != true and opts[:prune_direct_generic] == true and
      Map.has_key?(decl_map, view_target) and
      MapSet.member?(direct_targets, view_target)
  end

  @spec function_targets(ElmEx.IR.t(), Types.codegen_opts()) :: target_set()
  def function_targets(ir, opts) do
    decl_map = IRQueries.function_decl_map(ir)
    direct_targets = Host.direct_command_targets(ir, opts, decl_map)
    pruned_view? = prune_generic_view?(opts, decl_map, direct_targets)
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    view_fallback =
      if pruned_view? do
        MapSet.new()
      else
        view_streaming_fallback_targets(direct_targets, decl_map, opts)
      end

    direct_runtime_roots =
      cond do
        direct_render_only?(opts) ->
          generic_callees_from_direct_targets(direct_targets, decl_map)
          |> Enum.reject(&MapSet.member?(direct_targets, &1))

        opts[:prune_direct_generic] == true ->
          []

        true ->
          generic_callees_from_direct_targets(direct_targets, decl_map)
      end

    roots =
      if opts[:strip_dead_code] == false do
        Map.keys(decl_map)
      else
        Analysis.entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Kernel.++(MapSet.to_list(view_fallback))
      |> Enum.uniq()
      |> Enum.reject(fn target -> pruned_view? and target == view_target end)
      |> Enum.reject(fn target ->
        MapSet.member?(direct_targets, target) and not MapSet.member?(view_fallback, target)
      end)

    reachable_core =
      GenericReachability.reachable_targets(
        roots,
        decl_map,
        direct_render_excluded_targets(opts, direct_targets, decl_map, view_fallback),
        MapSet.new()
      )
      |> MapSet.difference(direct_targets)
      |> MapSet.union(view_fallback)
      |> then(fn targets -> if pruned_view?, do: MapSet.delete(targets, view_target), else: targets end)

    MapSet.union(
      reachable_core,
      helper_native_targets_from_generic(
        reachable_core,
        decl_map,
        view_fallback,
        opts,
        direct_targets
      )
    )
  end

  # Pull generic helpers for the view subgraph. When generic `view` is omitted for aplite
  # dual-codegen, reach from `view` itself so direct `_commands_append` still links.
  defp helper_native_targets_from_generic(
         generic_targets,
         decl_map,
         view_fallback,
         opts,
         direct_targets
       ) do
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    view_roots =
      cond do
        prune_generic_view?(opts, decl_map, direct_targets) ->
          [view_target]

        MapSet.size(view_fallback) > 0 ->
          MapSet.to_list(view_fallback)

        true ->
          []
      end

    if view_roots == [] do
      MapSet.new()
    else
      view_roots
      |> GenericReachability.reachable_targets(decl_map, MapSet.new(), MapSet.new())
      |> Enum.reject(&(&1 == view_target))
      |> MapSet.new()
      |> MapSet.difference(generic_targets)
    end
  end

  @spec wrapper_targets(ElmEx.IR.t(), Types.codegen_opts()) :: target_set()
  def wrapper_targets(ir, opts) do
    if opts[:prune_native_wrappers] == true do
      decl_map = IRQueries.function_decl_map(ir)
      direct_targets = Host.direct_command_targets(ir, opts, decl_map)
      wrapper_targets(ir, opts, decl_map, direct_targets)
    else
      function_targets(ir, opts)
    end
  end

  @spec wrapper_targets(
          ElmEx.IR.t(),
          Types.codegen_opts(),
          Types.function_decl_map(),
          target_set()
        ) :: target_set()
  def wrapper_targets(ir, opts, decl_map, direct_targets) do
    if opts[:prune_native_wrappers] == true do
      do_wrapper_targets(opts, decl_map, direct_targets)
    else
      function_targets(ir, opts)
    end
  end

  defp do_wrapper_targets(opts, decl_map, direct_targets) do
    pruned_view? = prune_generic_view?(opts, decl_map, direct_targets)
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    view_fallback =
      if pruned_view? do
        MapSet.new()
      else
        view_streaming_fallback_targets(direct_targets, decl_map, opts)
      end

    direct_runtime_roots =
      cond do
        direct_render_only?(opts) ->
          generic_wrapper_callees_from_direct_targets(direct_targets, decl_map)
          |> Enum.reject(&MapSet.member?(direct_targets, &1))

        opts[:prune_direct_generic] == true ->
          []

        true ->
          generic_wrapper_callees_from_direct_targets(direct_targets, decl_map)
      end

    roots =
      if opts[:strip_dead_code] == false do
        Map.keys(decl_map)
      else
        Analysis.entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Kernel.++(MapSet.to_list(view_fallback))
      |> Enum.uniq()
      |> Enum.reject(fn target -> pruned_view? and target == view_target end)
      |> Enum.reject(fn target ->
        MapSet.member?(direct_targets, target) and not MapSet.member?(view_fallback, target)
      end)

    reachable_core =
      GenericReachability.wrapper_reachable_targets(
        roots,
        decl_map,
        direct_render_excluded_targets(opts, direct_targets, decl_map, view_fallback),
        MapSet.new()
      )
      |> prune_zero_arity_internal_wrappers(decl_map)

    MapSet.union(
      reachable_core,
      helper_native_targets_from_generic(
        reachable_core,
        decl_map,
        view_fallback,
        opts,
        direct_targets
      )
    )
  end

  defp prune_zero_arity_internal_wrappers(targets, decl_map) when is_map(decl_map) do
    Enum.reduce(targets, targets, fn {_module_name, name} = target, acc ->
      case Map.fetch(decl_map, target) do
        {:ok, %{args: args}} when args in [nil, []] ->
          if name in @platform_wrapper_entries do
            acc
          else
            MapSet.delete(acc, target)
          end

        _ ->
          acc
      end
    end)
  end

  defp direct_render_only?(opts), do: opts[:direct_render_only] == true

  defp view_streaming_fallback_targets(direct_targets, decl_map, opts) do
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    case Map.fetch(decl_map, view_target) do
      {:ok, _} ->
        if opts[:stream_view_fallback] == true do
          MapSet.new([view_target | @stream_view_ui_helpers])
        else
          intersection =
            GenericReachability.reachable_targets(
              [view_target],
              decl_map,
              MapSet.new(),
              MapSet.new()
            )
            |> MapSet.delete(view_target)
            |> MapSet.intersection(direct_targets)

          if opts[:direct_render_only] == false and MapSet.member?(direct_targets, view_target) do
            MapSet.put(intersection, view_target)
          else
            intersection
          end
        end

      :error ->
        MapSet.new()
    end
  end

  defp direct_render_excluded_targets(opts, direct_targets, decl_map, view_fallback) do
    excluded =
      cond do
        direct_render_only?(opts) ->
          {_def_targets, _emit_targets, pruned} = Host.direct_command_target_sets(decl_map, opts)

          decl_map
          |> Map.keys()
          |> Enum.filter(&render_helper_target?/1)
          |> MapSet.new()
          |> MapSet.union(direct_targets)
          |> MapSet.union(pruned)
          |> MapSet.union(inlined_record_helpers(direct_targets, decl_map))

        opts[:prune_direct_generic] == true and MapSet.size(direct_targets) > 0 ->
          {_def_targets, _emit_targets, pruned} = Host.direct_command_target_sets(decl_map, opts)

          decl_map
          |> Map.keys()
          |> Enum.filter(&render_helper_target?/1)
          |> MapSet.new()
          |> MapSet.union(direct_targets)
          |> MapSet.union(pruned)
          |> MapSet.union(inlined_record_helpers(direct_targets, decl_map))

        true ->
          MapSet.new()
      end

    MapSet.difference(excluded, view_fallback)
  end

  defp render_helper_target?({module_name, _decl_name}) when is_binary(module_name) do
    module_name == "Pebble.Ui" or String.starts_with?(module_name, "Pebble.Ui.")
  end

  defp render_helper_target?(_target), do: false

  defp generic_callees_from_direct_targets(direct_targets, decl_map) do
    inlined_record_helpers = inlined_record_helpers(direct_targets, decl_map)

    direct_targets
    |> Enum.flat_map(fn {module_name, _decl_name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> GenericReachability.expr_callees(decl.expr, module_name, decl_map)
        :error -> []
      end
    end)
    |> Enum.reject(&render_helper_target?/1)
    |> Enum.reject(&MapSet.member?(inlined_record_helpers, &1))
  end

  defp generic_wrapper_callees_from_direct_targets(direct_targets, decl_map) do
    inlined_record_helpers = inlined_record_helpers(direct_targets, decl_map)

    direct_targets
    |> Enum.flat_map(fn {module_name, _decl_name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> GenericReachability.expr_wrapper_callees(decl.expr, module_name, decl_map)
        :error -> []
      end
    end)
    |> Enum.reject(&render_helper_target?/1)
    |> Enum.reject(&MapSet.member?(inlined_record_helpers, &1))
  end

  defp inlined_record_helpers(direct_targets, decl_map) do
    direct_helpers =
      Enum.reduce(direct_targets, MapSet.new(), fn {module_name, _decl_name} = target, acc ->
        case Map.fetch(decl_map, target) do
          {:ok, decl} -> walk_inlined_record_helpers(decl.expr, module_name, decl_map, acc)
          :error -> acc
        end
      end)

    view_helpers =
      decl_map
      |> Map.keys()
      |> Enum.filter(fn {_module_name, decl_name} -> decl_name == "view" end)
      |> Enum.reduce(MapSet.new(), fn {module_name, _decl_name} = target, acc ->
        case Map.fetch(decl_map, target) do
          {:ok, decl} -> walk_inlined_record_helpers(decl.expr, module_name, decl_map, acc)
          :error -> acc
        end
      end)

    MapSet.union(direct_helpers, view_helpers)
  end

  defp walk_inlined_record_helpers(expr, module_name, decl_map, acc) when is_map(expr) do
    env = %{__module__: module_name, __program_decls__: decl_map}

    case expr do
      %{op: :let_in, value_expr: value_expr, in_expr: in_expr} ->
        acc =
          case Expr.record_helper_target(value_expr, env) do
            nil ->
              acc

            target_key ->
              if NativeRecord.helper_let?("_", value_expr, env) or
                   NativeRecord.field_entries(value_expr, env) != :error do
                MapSet.put(acc, target_key)
              else
                acc
              end
          end

        walk_inlined_record_helpers(in_expr, module_name, decl_map, acc)

      _ ->
        expr
        |> Map.values()
        |> Enum.reduce(acc, &walk_inlined_record_helpers(&1, module_name, decl_map, &2))
    end
  end

  defp walk_inlined_record_helpers(values, module_name, decl_map, acc) when is_list(values) do
    Enum.reduce(values, acc, &walk_inlined_record_helpers(&1, module_name, decl_map, &2))
  end

  defp walk_inlined_record_helpers(_value, _module_name, _decl_map, acc), do: acc
end
