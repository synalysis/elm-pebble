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

  @spec function_targets(ElmEx.IR.t(), Types.codegen_opts()) :: target_set()
  def function_targets(ir, opts) do
    decl_map = IRQueries.function_decl_map(ir)
    direct_targets = Host.direct_command_targets(ir, opts, decl_map)

    direct_runtime_roots =
      if direct_render_only?(opts) do
        generic_callees_from_direct_targets(direct_targets, decl_map)
        |> Enum.reject(&MapSet.member?(direct_targets, &1))
      else
        generic_callees_from_direct_targets(direct_targets, decl_map)
      end

    roots =
      if opts[:strip_dead_code] == false do
        Map.keys(decl_map)
      else
        Analysis.entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Enum.reject(&MapSet.member?(direct_targets, &1))

    GenericReachability.reachable_targets(
      roots,
      decl_map,
      direct_render_excluded_targets(opts, direct_targets, decl_map),
      MapSet.new()
    )
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
    direct_runtime_roots =
      if direct_render_only?(opts) do
        generic_wrapper_callees_from_direct_targets(direct_targets, decl_map)
        |> Enum.reject(&MapSet.member?(direct_targets, &1))
      else
        generic_wrapper_callees_from_direct_targets(direct_targets, decl_map)
      end

    roots =
      if opts[:strip_dead_code] == false do
        Map.keys(decl_map)
      else
        Analysis.entry_roots(decl_map, opts)
      end
      |> Kernel.++(direct_runtime_roots)
      |> Enum.reject(&MapSet.member?(direct_targets, &1))

    GenericReachability.wrapper_reachable_targets(
      roots,
      decl_map,
      direct_render_excluded_targets(opts, direct_targets, decl_map),
      MapSet.new()
    )
  end

  defp direct_render_only?(opts), do: opts[:direct_render_only] == true

  defp direct_render_excluded_targets(opts, direct_targets, decl_map) do
    if direct_render_only?(opts) do
      {_def_targets, _emit_targets, pruned} = Host.direct_command_target_sets(decl_map, opts)

      decl_map
      |> Map.keys()
      |> Enum.filter(&render_helper_target?/1)
      |> MapSet.new()
      |> MapSet.union(direct_targets)
      |> MapSet.union(pruned)
    else
      MapSet.new()
    end
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
    Enum.reduce(direct_targets, MapSet.new(), fn {module_name, _decl_name} = target, acc ->
      case Map.fetch(decl_map, target) do
        {:ok, decl} -> walk_inlined_record_helpers(decl.expr, module_name, decl_map, acc)
        :error -> acc
      end
    end)
  end

  defp walk_inlined_record_helpers(expr, module_name, decl_map, acc) when is_map(expr) do
    env = %{__module__: module_name, __program_decls__: decl_map}

    acc =
      case expr do
        %{op: :let_in, value_expr: value_expr, in_expr: in_expr} ->
          acc =
            case Expr.record_helper_target(value_expr, env) do
              nil ->
                acc

              target_key ->
                if NativeRecord.helper_let?("_", value_expr, env) do
                  MapSet.put(acc, target_key)
                else
                  acc
                end
            end

          walk_inlined_record_helpers(in_expr, module_name, decl_map, acc)

        _ ->
          acc
      end

    expr
    |> Map.values()
    |> Enum.reduce(acc, &walk_inlined_record_helpers(&1, module_name, decl_map, &2))
  end

  defp walk_inlined_record_helpers(values, module_name, decl_map, acc) when is_list(values) do
    Enum.reduce(values, acc, &walk_inlined_record_helpers(&1, module_name, decl_map, &2))
  end

  defp walk_inlined_record_helpers(_value, _module_name, _decl_map, acc), do: acc
end
