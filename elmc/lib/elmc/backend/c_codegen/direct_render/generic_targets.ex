defmodule Elmc.Backend.CCodegen.DirectRender.GenericTargets do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Analysis
  alias Elmc.Backend.CCodegen.DirectRender.Emit.NativeRecord
  alias Elmc.Backend.CCodegen.DirectRender.RecordViewPeel
  alias Elmc.Backend.CCodegen.Expr
  alias Elmc.Backend.CCodegen.FusionSupport
  alias Elmc.Backend.CCodegen.FunctionCallAbi
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.GenericReachability
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Native.AngleMinute
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Native.Int, as: NativeInt
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

    prune_when_direct_scene? =
      opts[:prune_direct_generic] == true or opts[:direct_render_only] == true

    opts[:stream_view_fallback] != true and prune_when_direct_scene? and
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
          roots = direct_targets_for_generic_runtime_roots(direct_targets, opts, decl_map)

          generic_callees_from_direct_targets(roots, decl_map, opts)
          |> Enum.reject(&MapSet.member?(direct_targets, &1))

        opts[:prune_direct_generic] == true ->
          []

        true ->
          generic_callees_from_direct_targets(direct_targets, decl_map, opts)
      end

    direct_helper_seeds = direct_command_generic_helper_seeds(direct_targets, decl_map, opts)

    roots =
      if opts[:strip_dead_code] == false do
        Map.keys(decl_map)
      else
        Analysis.entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Kernel.++(direct_helper_seeds)
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
        MapSet.new(),
        pruned_generic_view_skip_callees(pruned_view?, entry_module)
      )
      |> MapSet.difference(direct_targets)
      |> MapSet.union(view_fallback)
      |> MapSet.union(MapSet.new(direct_helper_seeds))
      |> MapSet.difference(droppable_view_peeled_helpers(opts, decl_map, direct_targets, entry_module))

    plan_direct_boxed_callees =
      plan_required_direct_boxed_callees(reachable_core, decl_map, direct_targets)

    superseded_boxed =
      direct_command_superseded_boxed_targets(opts, decl_map, reachable_core, direct_targets)

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
    |> MapSet.union(plan_direct_boxed_callees)
    |> MapSet.difference(superseded_boxed)
    |> MapSet.difference(
      native_int_inlined_superseded_targets(opts, decl_map, reachable_core, direct_targets)
    )
    |> MapSet.difference(fusion_superseded_targets(reachable_core, decl_map))
    |> MapSet.difference(unused_streaming_ui_glue(opts, decl_map, direct_targets))
    |> MapSet.union(direct_render_outlined_native_int_callees(opts, direct_targets, decl_map))
  end

  # Whole-function fusion (moveBoard, initialBoard, …) inlines callees listed in
  # `Fusion.runtime_callees/4`. Drop standalone emit when every reachable caller
  # supersedes the callee and no other reachable function still needs it.
  defp fusion_superseded_targets(reachable_core, decl_map) do
    callers_of = fusion_caller_map(reachable_core, decl_map)

    fixed_point =
      Stream.iterate({MapSet.new(), MapSet.new()}, fn {dropped, _} ->
        new_dropped =
          reachable_core
          |> Enum.reduce(dropped, fn target, acc ->
            if MapSet.member?(acc, target) do
              acc
            else
              callers = Map.get(callers_of, target, [])
              external_callers = Enum.reject(callers, &(&1 == target))

              if external_callers != [] and
                   Enum.all?(external_callers, fn caller ->
                     MapSet.member?(acc, caller) or
                       FusionSupport.superseded_fusion_callee?(caller, target, decl_map)
                   end) do
                MapSet.put(acc, target)
              else
                acc
              end
            end
          end)

        {new_dropped, dropped}
      end)
      |> Stream.drop(1)
      |> Enum.find(fn {current, prev} -> MapSet.equal?(current, prev) end)
      |> elem(0)

    expand_fusion_superseded_native(fixed_point, reachable_core, decl_map, callers_of)
  end

  defp expand_fusion_superseded_native(superseded, reachable_core, decl_map, callers_of) do
    opts = Process.get(:elmc_codegen_opts, %{})

    if Elmc.Backend.SizeProfile.fusion_supersede_native?(opts) do
      native_orphans =
        reachable_core
        |> Enum.filter(fn target ->
          native_scalar_helper_target?(target, decl_map) and
            not MapSet.member?(superseded, target) and
            orphan_native_helper?(target, superseded, callers_of)
        end)
        |> MapSet.new()

      MapSet.union(superseded, native_orphans)
    else
      superseded
    end
  end

  defp native_scalar_helper_target?({module_name, name}, decl_map) do
    case Map.get(decl_map, {module_name, name}) do
      %{args: [_arg]} = decl ->
        NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map)

      _ ->
        false
    end
  end

  defp orphan_native_helper?(target, superseded, callers_of) do
    callers = Map.get(callers_of, target, [])
    external_callers = Enum.reject(callers, &(&1 == target))

    external_callers != [] and Enum.all?(external_callers, &MapSet.member?(superseded, &1))
  end

  defp fusion_caller_map(reachable_core, decl_map) do
    reachable_core
    |> Enum.flat_map(fn {mod, name} = caller ->
      case Map.fetch(decl_map, {mod, name}) do
        {:ok, %{expr: expr}} ->
          GenericReachability.expr_callees(expr, mod, decl_map)
          |> Enum.map(fn callee -> {callee, caller} end)

        :error ->
          []
      end
    end)
    |> Enum.group_by(fn {callee, _} -> callee end, fn {_, caller} -> caller end)
    |> Map.new(fn {callee, callers} -> {callee, Enum.uniq(callers)} end)
  end

  # Direct `_commands_append` replaces boxed `List RenderOp` bodies for the same target.
  # Drop generic RC emit unless worker/update/init still calls the boxed ABI.
  defp direct_command_superseded_boxed_targets(opts, decl_map, reachable_core, direct_targets) do
    if supersede_direct_render_op_boxed?(opts) do
      {_def_targets, emit_targets, _pruned} = Host.direct_command_target_sets(decl_map, opts)

      render_op_defs =
        emit_targets
        |> Enum.filter(fn key ->
          case Map.fetch(decl_map, key) do
            {:ok, decl} -> render_op_list_return?(decl)
            :error -> false
          end
        end)
        |> MapSet.new()

      required_boxed =
        plan_required_direct_boxed_callees(reachable_core, decl_map, direct_targets)
        |> MapSet.intersection(render_op_defs)

      MapSet.difference(render_op_defs, required_boxed)
      |> MapSet.union(polar_point_superseded_boxed(opts, decl_map, reachable_core))
    else
      MapSet.new()
    end
  end

  # Native-int helpers such as angleFromMinute are inlined via elmc_angle_from_minute (or
  # Native.Int inline) in direct `_commands_append`; drop standalone plan emit when every
  # use site lives under direct scene targets.
  defp native_int_inlined_superseded_targets(opts, decl_map, reachable_core, direct_targets) do
    if supersede_direct_render_op_boxed?(opts) do
      inlined = inlined_native_int_helpers(direct_targets, decl_map)

      required =
        plan_required_direct_boxed_callees(reachable_core, decl_map, direct_targets)
        |> MapSet.union(
          plan_required_native_int_callees(reachable_core, decl_map, direct_targets)
        )

      MapSet.difference(inlined, required)
    else
      MapSet.new()
    end
  end

  defp plan_required_native_int_callees(targets, decl_map, direct_targets) do
    targets
    |> Enum.reject(&MapSet.member?(direct_targets, &1))
    |> Enum.flat_map(fn {module_name, _name} = key ->
      case Map.fetch(decl_map, key) do
        {:ok, decl} ->
          GenericReachability.expr_callees(decl.expr, module_name, decl_map)

        :error ->
          []
      end
    end)
    |> Enum.filter(&native_int_inlined_superseded_target?(&1, decl_map))
    |> MapSet.new()
  end

  defp native_int_inlined_superseded_target?({module_name, _name} = target, decl_map) do
    case Map.get(decl_map, target) do
      %{args: [arg_name], expr: body} when is_binary(arg_name) ->
        decl = Map.get(decl_map, target)

        NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) and
          NativeFunctionCall.return_kind(decl, module_name, decl_map) == :native_int and
          (AngleMinute.body_expr?(body) or
             NativeInt.inline_function_expr?(
               target,
               [%{op: :var, name: arg_name}],
               %{__program_decls__: decl_map, __module__: module_name}
             ))

      _ ->
        false
    end
  end

  defp inlined_native_int_helpers(direct_targets, decl_map) do
    direct_targets
    |> Enum.reduce(MapSet.new(), fn {module_name, _decl_name} = target, acc ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} ->
          walk_inlined_native_int_helpers(decl.expr, module_name, decl_map, acc)

        :error ->
          acc
      end
    end)
    |> MapSet.filter(&native_int_inlined_superseded_target?(&1, decl_map))
  end

  defp walk_inlined_native_int_helpers(expr, module_name, decl_map, acc) when is_map(expr) do
    acc =
      case native_int_call_target(expr, module_name) do
        target when not is_nil(target) ->
          if native_int_inlined_superseded_target?(target, decl_map) do
            MapSet.put(acc, target)
          else
            acc
          end

        _ ->
          acc
      end

    expr
    |> Map.values()
    |> Enum.reduce(acc, &walk_inlined_native_int_helpers(&1, module_name, decl_map, &2))
  end

  defp walk_inlined_native_int_helpers(values, module_name, decl_map, acc) when is_list(values) do
    Enum.reduce(values, acc, &walk_inlined_native_int_helpers(&1, module_name, decl_map, &2))
  end

  defp walk_inlined_native_int_helpers(_value, _module_name, _decl_map, acc), do: acc

  defp native_int_call_target(%{op: :call, name: name, args: [_arg]}, module_name)
       when is_binary(name),
       do: {module_name, name}

  defp native_int_call_target(%{op: :qualified_call, target: target, args: [_arg]}, _module_name)
       when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {mod, name} -> {mod, name}
      _ -> nil
    end
  end

  defp native_int_call_target(_, _), do: nil

  # Direct `_commands_append` inlines native-int helpers when `NativeInt.inline_function_expr?/3`
  # succeeds at each call site. When a call site falls back to `NativeFunctionCall.compile_scalar/6`,
  # the callee must still be emitted even though it is not reachable from generic entry roots.
  defp direct_render_outlined_native_int_callees(opts, direct_targets, decl_map) do
    if supersede_direct_render_op_boxed?(opts) and MapSet.size(direct_targets) > 0 do
      direct_targets
      |> Enum.reduce(MapSet.new(), fn {module_name, _decl_name} = direct_key, acc ->
        case Map.fetch(decl_map, direct_key) do
          {:ok, decl} ->
            walk_direct_render_outlined_calls(decl.expr, module_name, decl_map, acc)

          :error ->
            acc
        end
      end)
      |> expand_outlined_native_int_dependencies(decl_map)
    else
      MapSet.new()
    end
  end

  defp walk_direct_render_outlined_calls(expr, module_name, decl_map, acc) when is_map(expr) do
    acc =
      case call_target_from_expr(expr, module_name) do
        target when is_tuple(target) ->
          args = call_args_from_expr(expr)

          if direct_render_outlined_native_call?(target, args, module_name, decl_map) do
            MapSet.put(acc, target)
          else
            acc
          end

        _ ->
          acc
      end

    expr
    |> Map.values()
    |> Enum.reduce(acc, &walk_direct_render_outlined_calls(&1, module_name, decl_map, &2))
  end

  defp walk_direct_render_outlined_calls(values, module_name, decl_map, acc) when is_list(values) do
    Enum.reduce(values, acc, &walk_direct_render_outlined_calls(&1, module_name, decl_map, &2))
  end

  defp walk_direct_render_outlined_calls(_value, _module_name, _decl_map, acc), do: acc

  defp direct_render_outlined_native_call?(target_key, args, module_name, decl_map) do
    case Map.get(decl_map, target_key) do
      decl when is_map(decl) ->
        {mod, _} = target_key

        NativeFunctionCall.native_scalar_fn?(decl, mod, decl_map) and
          FunctionCallAbi.primary_lowered?(decl, mod, decl_map) and
          NativeFunctionCall.return_kind(decl, mod, decl_map) in [:native_int, :native_bool] and
          not NativeInt.inline_function_expr?(
            target_key,
            args,
            %{__program_decls__: decl_map, __module__: module_name}
          )

      _ ->
        false
    end
  end

  defp expand_outlined_native_int_dependencies(outlined, decl_map) do
    Enum.reduce(outlined, outlined, fn target, acc ->
      case Map.get(decl_map, target) do
        %{expr: expr} ->
          {mod, _} = target

          callees =
            GenericReachability.expr_callees(expr, mod, decl_map)
            |> Enum.filter(fn callee ->
              case Map.get(decl_map, callee) do
                decl when is_map(decl) ->
                  {callee_mod, _} = callee

                  NativeFunctionCall.native_scalar_fn?(decl, callee_mod, decl_map) and
                    FunctionCallAbi.primary_lowered?(decl, callee_mod, decl_map)

                _ ->
                  false
              end
            end)
            |> MapSet.new()

          MapSet.union(acc, callees)

        _ ->
          acc
      end
    end)
  end

  defp call_target_from_expr(%{op: :call, name: name, args: _args}, module_name)
       when is_binary(name),
       do: {module_name, name}

  defp call_target_from_expr(%{op: :qualified_call, target: target, args: _args}, _module_name)
       when is_binary(target) do
    case Host.split_qualified_function_target(Host.normalize_special_target(target)) do
      {mod, name} -> {mod, name}
      _ -> nil
    end
  end

  defp call_target_from_expr(_, _), do: nil

  defp call_args_from_expr(%{op: :call, args: args}), do: args
  defp call_args_from_expr(%{op: :qualified_call, args: args}), do: args

  # Polar helpers are inlined via elmc_polar_point_x/y in direct `_commands_append`.
  defp polar_point_superseded_boxed(opts, decl_map, reachable_core) do
    if supersede_direct_render_op_boxed?(opts) do
      decl_map
      |> Map.keys()
      |> Enum.filter(&Elmc.Backend.CCodegen.Native.PolarPoint.polar_point_target?(&1, decl_map))
      |> MapSet.new()
      |> MapSet.difference(
        plan_required_direct_boxed_callees(reachable_core, decl_map, MapSet.new())
      )
    else
      MapSet.new()
    end
  end

  defp supersede_direct_render_op_boxed?(opts) do
    opts[:direct_render_only] == true or
      Elmc.Backend.SizeProfile.aggressive_direct_render?(opts)
  end

  defp plan_required_direct_boxed_callees(targets, decl_map, direct_targets) do
    if MapSet.size(direct_targets) == 0 do
      MapSet.new()
    else
      targets
      |> Enum.reject(&MapSet.member?(direct_targets, &1))
      |> Enum.flat_map(fn {module_name, _name} = key ->
        case Map.fetch(decl_map, key) do
          {:ok, decl} ->
            GenericReachability.expr_callees(decl.expr, module_name, decl_map)

          :error ->
            []
        end
      end)
      |> MapSet.new()
      |> MapSet.intersection(direct_targets)
    end
  end

  # `toUiNode` expands to windowStack/window/canvasLayer in Elm, but direct scene
  # emit replaces that glue; keep generic codegen from emitting the unused helpers.
  defp unused_streaming_ui_glue(opts, decl_map, direct_targets) do
    if opts[:stream_view_fallback] == true do
      MapSet.new()
    else
      entry_module = opts[:entry_module] || "Main"
      view_target = {entry_module, "view"}

      drop? =
        prune_generic_view?(opts, decl_map, direct_targets) or
          (direct_render_only?(opts) and MapSet.member?(direct_targets, view_target))

      if drop?, do: MapSet.new(@stream_view_ui_helpers), else: MapSet.new()
    end
  end

  # Pull generic helpers for the view subgraph. When generic `view` is omitted for aplite
  # dual-codegen, reach from `view` itself so direct `_commands_append` still links.
  defp helper_native_targets_from_generic(
         generic_targets,
         decl_map,
         view_fallback,
         opts,
         _direct_targets
       ) do
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    view_roots =
      if MapSet.size(view_fallback) > 0 do
        MapSet.to_list(view_fallback)
      else
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
          roots = direct_targets_for_generic_runtime_roots(direct_targets, opts, decl_map)

          generic_wrapper_callees_from_direct_targets(roots, decl_map, opts)
          |> Enum.reject(&MapSet.member?(direct_targets, &1))

        opts[:prune_direct_generic] == true ->
          []

        true ->
          generic_wrapper_callees_from_direct_targets(direct_targets, decl_map, opts)
      end

    direct_helper_seeds = direct_command_generic_helper_seeds(direct_targets, decl_map, opts)

    roots =
      if opts[:strip_dead_code] == false do
        Map.keys(decl_map)
      else
        Analysis.entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Kernel.++(direct_helper_seeds)
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
      |> MapSet.difference(direct_targets)
      |> MapSet.union(MapSet.new(direct_helper_seeds))
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

  defp direct_targets_for_helper_analysis(direct_targets, opts, decl_map, entry_module) do
    view_target = {entry_module, "view"}

    if prune_generic_view?(opts, decl_map, direct_targets) do
      MapSet.delete(direct_targets, view_target)
    else
      direct_targets
    end
  end

  defp pruned_generic_view_skip_callees(false, _entry_module), do: MapSet.new()

  defp pruned_generic_view_skip_callees(true, entry_module),
    do: MapSet.new([{entry_module, "view"}])

  defp direct_targets_for_generic_runtime_roots(direct_targets, opts, decl_map) do
    entry_module = opts[:entry_module] || "Main"
    view_target = {entry_module, "view"}

    if prune_generic_view?(opts, decl_map, direct_targets) do
      MapSet.delete(direct_targets, view_target)
    else
      direct_targets
    end
  end

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

  defp direct_command_generic_helper_seeds(direct_targets, decl_map, opts) do
    entry_module = opts[:entry_module] || "Main"

    # Direct `_scene_append` inlines the view grid when generic `view` is pruned.
    pruned_view_callees = []

    direct_only_boxed_seeds =
      if prune_generic_view?(opts, decl_map, direct_targets) do
        direct_command_boxed_callees(direct_targets, decl_map, opts, entry_module)
        |> MapSet.to_list()
      else
        []
      end

    pruned_display_seeds =
      pruned_view_display_helper_seeds(opts, decl_map, direct_targets, entry_module)

    view_peeled_helpers = droppable_view_peeled_helpers(opts, decl_map, direct_targets, entry_module)

    mixed_abi_helpers = mixed_abi_outline_helpers(direct_targets, decl_map)

    mixed_direct_boxed_callees =
      boxed_direct_callees_of_mixed_helpers(mixed_abi_helpers, direct_targets, decl_map)

    (pruned_view_callees ++ direct_only_boxed_seeds ++ pruned_display_seeds ++ mixed_abi_helpers ++
       mixed_direct_boxed_callees)
    |> Enum.reject(&MapSet.member?(view_peeled_helpers, &1))
    |> Enum.uniq()
  end

  # When generic `view` is pruned, direct scene emit still calls boxed helpers that
  # build the face display record (`faceOps` → `faceDisplay` → corner/time helpers).
  # Reach only entry-module helpers under `faceDisplay`; do not follow `Yes.Render.face`
  # or other render-op-list callees (those are inlined via direct `_commands_append`).
  defp pruned_view_display_helper_seeds(opts, decl_map, direct_targets, entry_module) do
    if prune_generic_view?(opts, decl_map, direct_targets) do
      view_target = {entry_module, "view"}

      case Map.fetch(decl_map, view_target) do
        {:ok, %{expr: view_expr}} ->
          inner = ui_node_inner_expr(view_expr) || view_expr

          glue_seeds =
            inner
            |> GenericReachability.expr_callees(entry_module, decl_map)
            |> Enum.filter(fn {module_name, _} = key ->
              module_name == entry_module and
                case Map.fetch(decl_map, key) do
                  {:ok, decl} -> render_op_list_return?(decl)
                  :error -> false
                end
            end)

          face_display_roots =
            Enum.flat_map(glue_seeds, fn {glue_module, _name} = glue_key ->
              case Map.fetch(decl_map, glue_key) do
                {:ok, %{expr: expr}} ->
                  GenericReachability.expr_callees(expr, glue_module, decl_map)

                :error ->
                  []
              end
            end)
            |> Enum.filter(fn {module_name, _} -> module_name == entry_module end)
            |> Enum.filter(&pruned_view_helper_seed_root?(&1, decl_map))

          face_display_roots
          |> expand_pruned_view_entry_helper_seeds(entry_module, decl_map, 4, MapSet.new())
          |> Enum.reject(&pruned_view_helper_seed_excluded?(&1, decl_map))
          |> Enum.uniq()

        :error ->
          []
      end
    else
      []
    end
  end

  defp pruned_view_helper_seed_root?(key, decl_map) do
    case Map.fetch(decl_map, key) do
      {:ok, decl} -> not render_op_list_return?(decl)
      :error -> false
    end
  end

  defp pruned_view_point_helper_seed?(%{type: type, args: args}) when is_list(args) do
    is_binary(type) and length(args) == 2 and String.contains?(type, "Point")
  end

  defp pruned_view_point_helper_seed?(_), do: false

  defp pruned_view_boxed_helper_seed?(decl) do
    case Map.get(decl, :type) do
      type when is_binary(type) ->
        String.contains?(type, "String") and not String.contains?(type, "RenderOp")

      _ ->
        false
    end
  end

  defp pruned_view_helper_seed_excluded?({module_name, name}, decl_map) do
    render_op_list_return?(Map.get(decl_map, {module_name, name}, %{})) or
      name in ["view", "faceOps", "faceDisplay"]
  end

  defp expand_pruned_view_entry_helper_seeds([], _entry_module, _decl_map, _depth, visited),
    do: MapSet.to_list(visited)

  defp expand_pruned_view_entry_helper_seeds(_frontier, _entry_module, _decl_map, 0, visited),
    do: MapSet.to_list(visited)

  defp expand_pruned_view_entry_helper_seeds(frontier, entry_module, decl_map, depth, visited) do
    {next, visited} =
      Enum.reduce(frontier, {[], visited}, fn {module_name, _name} = key, {pending, seen} ->
        if MapSet.member?(seen, key) do
          {pending, seen}
        else
          seen = MapSet.put(seen, key)

          callees =
            case Map.fetch(decl_map, key) do
              {:ok, %{expr: expr}} ->
                GenericReachability.expr_callees(expr, module_name, decl_map)
                |> Enum.filter(fn {mod, _} -> mod == entry_module end)
                |> Enum.filter(&pruned_view_helper_seed_root?(&1, decl_map))

              :error ->
                []
            end

          {pending ++ callees, seen}
        end
      end)

    next = Enum.uniq(next)

    expand_pruned_view_entry_helper_seeds(next, entry_module, decl_map, depth - 1, visited)
  end

  defp view_peeled_helper_set(opts, decl_map, direct_targets, entry_module) do
    view_target = {entry_module, "view"}

    with true <- prune_generic_view?(opts, decl_map, direct_targets),
         {:ok, %{expr: view_expr}} <- Map.fetch(decl_map, view_target) do
      env = %{__program_decls__: decl_map, __module__: entry_module}

      view_expr
      |> RecordViewPeel.peeled_helpers_at_view(env)
      |> MapSet.new()
    else
      _ -> MapSet.new()
    end
  end

  # Record-view peel marks helpers whose bodies are record literals, but direct command
  # emit may still call them with the boxed ABI (for example `midpoint` inside `Ui.line`).
  defp droppable_view_peeled_helpers(opts, decl_map, direct_targets, entry_module) do
    peeled = view_peeled_helper_set(opts, decl_map, direct_targets, entry_module)
    view_target = {entry_module, "view"}

    view_callees =
      if prune_generic_view?(opts, decl_map, direct_targets) and Map.has_key?(decl_map, view_target) do
        case Map.fetch(decl_map, view_target) do
          {:ok, %{expr: expr}} ->
            generic_callees_under_ui_node(
              expr,
              entry_module,
              direct_targets,
              decl_map,
              MapSet.new([view_target])
            )

          :error ->
            []
        end
      else
        []
      end

    required =
      peeled
      |> MapSet.intersection(MapSet.new(view_callees))
      |> MapSet.union(direct_command_boxed_callees(direct_targets, decl_map, opts, entry_module))
      |> MapSet.union(MapSet.new(pruned_view_display_helper_seeds(opts, decl_map, direct_targets, entry_module)))

    MapSet.difference(peeled, required)
  end

  defp direct_command_boxed_callees(direct_targets, decl_map, opts, entry_module) do
    pruned_view? = prune_generic_view?(opts, decl_map, direct_targets)
    analysis_targets = direct_targets_for_helper_analysis(direct_targets, opts, decl_map, entry_module)

    render_op_def_targets =
      if supersede_direct_render_op_boxed?(opts) do
        direct_render_op_def_targets(decl_map, opts)
      else
        MapSet.new()
      end

    boxed =
      analysis_targets
      |> Enum.flat_map(fn {module_name, _name} = target ->
        case Map.fetch(decl_map, target) do
          {:ok, decl} ->
            GenericReachability.expr_callees(decl.expr, module_name, decl_map)
            |> Enum.reject(&MapSet.member?(render_op_def_targets, &1))
            |> Enum.reject(&polar_point_boxed_callee?(&1, decl_map, opts))

          :error ->
            []
        end
      end)

    view_boxed =
      if pruned_view? do
        view_target = {entry_module, "view"}

        case Map.fetch(decl_map, view_target) do
          {:ok, %{expr: expr}} ->
            generic_callees_under_ui_node(
              expr,
              entry_module,
              direct_targets,
              decl_map,
              MapSet.new([view_target])
            )
            |> Enum.filter(fn {module_name, _} = key ->
              module_name == entry_module and
                not MapSet.member?(direct_targets, key) and
                case Map.fetch(decl_map, key) do
                  {:ok, decl} ->
                    pruned_view_boxed_helper_seed?(decl) or pruned_view_point_helper_seed?(decl)

                  :error ->
                    false
                end
            end)

          :error ->
            []
        end
      else
        []
      end

    MapSet.new(boxed ++ view_boxed)
  end

  defp polar_point_boxed_callee?(target, decl_map, opts) do
    supersede_direct_render_op_boxed?(opts) and
      Elmc.Backend.CCodegen.Native.PolarPoint.polar_point_target?(target, decl_map)
  end

  defp mixed_abi_outline_helpers(direct_targets, decl_map) do
    inlined = inlined_record_helpers(direct_targets, decl_map)

    direct_targets
    |> MapSet.to_list()
    |> GenericReachability.reachable_targets(decl_map, MapSet.new(), MapSet.new())
    |> Enum.filter(fn {module_name, _name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} ->
          FunctionEmit.mixed_direct_abi?(decl, module_name, decl_map) and
            (MapSet.member?(direct_targets, target) or MapSet.member?(inlined, target))

        :error ->
          false
      end
    end)
  end

  # Mixed-ABI direct `_native` bodies (for example `downloadedTangram`) call other direct
  # command helpers with the boxed `(out, args, argc)` ABI. Those callees must stay in
  # generic codegen even though they are also direct scene targets.
  defp boxed_direct_callees_of_mixed_helpers(mixed_abi_helpers, direct_targets, decl_map) do
    mixed_set = MapSet.new(mixed_abi_helpers)

    mixed_abi_helpers
    |> GenericReachability.reachable_targets(decl_map, MapSet.new(), MapSet.new())
    |> Enum.filter(fn target ->
      MapSet.member?(direct_targets, target) and not MapSet.member?(mixed_set, target)
    end)
  end

  defp generic_callees_under_ui_node(expr, module_name, direct_targets, decl_map, seen) do
    inner = ui_node_inner_expr(expr) || expr

    inner
    |> GenericReachability.expr_callees(module_name, decl_map)
    |> Enum.flat_map(fn callee ->
      cond do
        MapSet.member?(direct_targets, callee) ->
          []

        MapSet.member?(seen, callee) ->
          []

        true ->
          case Map.fetch(decl_map, callee) do
            {:ok, %{expr: callee_expr}} ->
              nested =
                generic_callees_under_ui_node(
                  callee_expr,
                  elem(callee, 0),
                  direct_targets,
                  decl_map,
                  MapSet.put(seen, callee)
                )

              if streaming_glue_target?(callee, direct_targets, decl_map) do
                nested
              else
                [callee | nested]
              end

            :error ->
              [callee]
          end
      end
    end)
    |> Enum.uniq()
  end

  # Peel `Ui.toUiNode (faceOps model)`-style wrappers that return render-op lists
  # but are not themselves direct command targets.
  defp streaming_glue_target?(target, direct_targets, decl_map) do
    case Map.fetch(decl_map, target) do
      {:ok, decl} ->
        not MapSet.member?(direct_targets, target) and render_op_list_return?(decl)

      :error ->
        false
    end
  end

  defp render_op_list_return?(%{type: type}) when is_binary(type) do
    String.contains?(type, "List") and String.contains?(type, "RenderOp")
  end

  defp render_op_list_return?(_decl), do: false

  defp ui_node_inner_expr(%{op: :qualified_call, target: target, args: [inner]})
       when target in ["Pebble.Ui.toUiNode"],
       do: inner

  defp ui_node_inner_expr(_expr), do: nil

  defp generic_callees_from_direct_targets(direct_targets, decl_map, opts) do
    inlined_record_helpers = inlined_record_helpers(direct_targets, decl_map)

    render_op_def_targets = direct_render_op_def_targets(decl_map, opts)

    direct_targets
    |> Enum.flat_map(fn {module_name, _decl_name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> GenericReachability.expr_callees(decl.expr, module_name, decl_map)
        :error -> []
      end
    end)
    |> Enum.reject(&render_helper_target?/1)
    |> Enum.reject(&MapSet.member?(inlined_record_helpers, &1))
    |> Enum.reject(&MapSet.member?(render_op_def_targets, &1))
  end

  defp generic_wrapper_callees_from_direct_targets(direct_targets, decl_map, opts) do
    inlined_record_helpers = inlined_record_helpers(direct_targets, decl_map)

    render_op_def_targets = direct_render_op_def_targets(decl_map, opts)

    direct_targets
    |> Enum.flat_map(fn {module_name, _decl_name} = target ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> GenericReachability.expr_wrapper_callees(decl.expr, module_name, decl_map)
        :error -> []
      end
    end)
    |> Enum.reject(&render_helper_target?/1)
    |> Enum.reject(&MapSet.member?(inlined_record_helpers, &1))
    |> Enum.reject(&MapSet.member?(render_op_def_targets, &1))
  end

  defp direct_render_op_def_targets(decl_map, opts) do
    if supersede_direct_render_op_boxed?(opts) do
      {_def_targets, emit_targets, _pruned} = Host.direct_command_target_sets(decl_map, opts)

      emit_targets
      |> Enum.filter(fn key ->
        case Map.fetch(decl_map, key) do
          {:ok, decl} -> render_op_list_return?(decl)
          :error -> false
        end
      end)
      |> MapSet.new()
    else
      MapSet.new()
    end
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
