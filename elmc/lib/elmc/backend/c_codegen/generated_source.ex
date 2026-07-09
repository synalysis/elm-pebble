defmodule Elmc.Backend.CCodegen.GeneratedSource do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.DirectRender.Analysis, as: DirectRenderAnalysis
  alias Elmc.Backend.CCodegen.DirectRender.Analysis
  alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
  alias Elmc.Backend.CCodegen.DirectRender.Registry, as: DirectRenderRegistry
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.LayoutSolver
  alias Elmc.Backend.CCodegen.SchemaRegistry
  alias Elmc.Backend.CCodegen.MacroReachability
  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Native.DefRegistry
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.RecordCompile
  alias Elmc.Backend.CCodegen.RecordFieldMacros
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.CCodegen.ValueSlots
  alias Elmc.Backend.Pebble.IRAnalysis

  defp finalize_source(source), do: CSource.format(source)

  @spec reset_process_state!() :: :ok
  def reset_process_state! do
    reset_emit_probe_state!()

    for {key, _} <- Process.get(), delete_codegen_process_key?(key) do
      Process.delete(key)
    end

    :ok
  end

  @spec reset_emit_probe_state!() :: :ok
  def reset_emit_probe_state! do
    ValueSlots.reset()
    Elmc.Backend.CCodegen.DirectRender.RecordViewPeel.reset_cache!()
    DefRegistry.reset()
    RecordCompile.reset_rec_values_suffix()

    for {key, _} <- Process.get(), delete_emit_probe_process_key?(key) do
      Process.delete(key)
    end

    :ok
  end

  @spec capture_lambda_emit_state!() :: map()
  def capture_lambda_emit_state! do
    %{
      lambdas: Process.get(:elmc_lambdas, []),
      defs: Process.get(:elmc_lambda_defs, %{}),
      counter: Process.get(:elmc_lambda_counter, 0),
      emitted: Process.get(:elmc_lambda_emitted_names, MapSet.new())
    }
  end

  @spec restore_lambda_emit_state!(map()) :: :ok
  def restore_lambda_emit_state!(state) do
    Process.put(:elmc_lambdas, Map.get(state, :lambdas, []))
    Process.put(:elmc_lambda_defs, Map.get(state, :defs, %{}))
    Process.put(:elmc_lambda_counter, Map.get(state, :counter, 0))
    Process.put(:elmc_lambda_emitted_names, Map.get(state, :emitted, MapSet.new()))
    :ok
  end

  @compile_session_process_keys ~w(
    elmc_lambdas
    elmc_lambda_counter
    elmc_lambda_defs
    elmc_lambda_emitted_names
    elmc_rc_required
    elmc_program_decls
    elmc_codegen_opts
    elmc_exported_targets
    elmc_wrapper_targets
    elmc_direct_call_targets
    elmc_function_arities
    elmc_storage_plans
    elmc_schema_registry
    elmc_layout_coercion_diagnostics
    elmc_plan_primary_fallbacks
    elmc_record_field_types
    elmc_record_alias_shapes
    elmc_record_field_macros
    elmc_union_type_names
    elmc_union_constructor_macros
    elmc_constructor_tags
    elmc_enum_types
    elmc_pebble_msg_names
    elmc_msg_constructor_payload_specs
    elmc_named_record_literals
    elmc_native_boxed_rc_abi
    elmc_native_bool_rc_abi
    elmc_vector_resource_slots
    elmc_bitmap_resource_slots
    elmc_animation_resource_slots
    elmc_font_resource_slots
    elmc_speaker_sample_resource_slots
  )a

  defp delete_emit_probe_process_key?(key) when key in @compile_session_process_keys, do: false

  defp delete_emit_probe_process_key?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.starts_with?("elmc_")
  end

  defp delete_emit_probe_process_key?({:record_view_peel, _, _, _}), do: true
  defp delete_emit_probe_process_key?({:elmc_subexpr_cache, _}), do: true
  defp delete_emit_probe_process_key?({:elmc_subexpr_shared, _}), do: true
  defp delete_emit_probe_process_key?(_), do: false

  defp delete_codegen_process_key?(:elmc_layout_coercion_diagnostics), do: false
  defp delete_codegen_process_key?(:elmc_plan_primary_fallbacks), do: false

  defp delete_codegen_process_key?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.starts_with?("elmc_")
  end

  defp delete_codegen_process_key?({:record_view_peel, _, _, _}), do: true
  defp delete_codegen_process_key?({:elmc_subexpr_cache, _}), do: true
  defp delete_codegen_process_key?({:elmc_subexpr_shared, _}), do: true
  defp delete_codegen_process_key?(_), do: false

  defp rc_required_opts(opts, direct_command_targets) when is_list(opts),
    do: Keyword.put(opts, :direct_command_targets, direct_command_targets)

  defp rc_required_opts(%{} = opts, direct_command_targets),
    do: Map.put(opts, :direct_command_targets, direct_command_targets)

  # Direct scene helpers are linked for every Pebble platform, including aplite.
  defp direct_scene_guard(content, _opts, _ir) when is_binary(content) do
    String.trim_trailing(content)
  end

  @spec header(ElmEx.IR.t(), Types.codegen_opts()) :: String.t()
  def header(ir, opts) do
    reset_process_state!()
    Process.put(:elmc_codegen_opts, opts)
    Process.put(:elmc_constructor_tags, IRQueries.constructor_tag_map(ir))

    direct_cmd_decls = DirectRenderRegistry.decls(ir, opts)
    decl_map = IRQueries.function_decl_map(ir)
    direct_command_targets = Host.direct_command_targets(ir, opts, decl_map)
    wrapper_targets = GenericTargets.wrapper_targets(ir, opts)
    Process.put(:elmc_wrapper_targets, wrapper_targets)
    exported_targets = Analysis.exported_function_targets(decl_map, opts, direct_command_targets)
    _ = RcRequired.run!(decl_map, rc_required_opts(opts, direct_command_targets))

    function_decls =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(fn decl ->
          target = {mod.name, decl.name}

          decl.kind == :function &&
            MapSet.member?(exported_targets, target) &&
            (MapSet.member?(wrapper_targets, target) ||
               not NativeFunctionCall.native_scalar_fn?(decl, mod.name, decl_map))
        end)
        |> Enum.map(fn decl ->
          c_name = Util.module_fn_name(mod.name, decl.name)
          emit_wrapper? = MapSet.member?(wrapper_targets, {mod.name, decl.name})

          FunctionEmit.boxed_function_prototype(
            decl,
            mod.name,
            c_name,
            emit_wrapper?,
            decl_map
          )
        end)
      end)
      |> Enum.join("\n")

    """
    #ifndef ELMC_GENERATED_H
    #define ELMC_GENERATED_H

    #include "../runtime/elmc_runtime.h"
    #include "../ports/elmc_ports.h"
    #{function_decls}
    #{direct_cmd_decls}

    #endif
    """
    |> tap(fn _ -> :ok end)
  end

  @doc """
  Install Process-backed codegen state shared by monolithic and per-module emit paths.
  Caller must invoke `reset_process_state!/0` when the session ends (see `with_emit_session/3`).
  """
  @spec prepare_emit_session!(ElmEx.IR.t(), Types.codegen_opts()) :: :ok
  def prepare_emit_session!(ir, opts) do
    reset_process_state!()
    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_plan_closure_emitted, MapSet.new())
    Process.put(:elmc_lambda_counter, 0)
    Process.put(:elmc_lambda_defs, %{})
    Process.put(:elmc_lambda_emitted_names, MapSet.new())
    Process.put(:elmc_borrowed_field_refs, MapSet.new())
    RecordCompile.reset_rec_values_suffix()

    function_arities =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, length(decl.args || [])} end)
      end)
      |> Map.new()

    constructor_tags = IRQueries.constructor_tag_map(ir)
    decl_map = IRQueries.function_decl_map(ir)
    generic_targets = GenericTargets.function_targets(ir, opts)

    reachable_for_fields =
      generic_targets
      |> MapSet.union(Host.direct_command_targets(ir, opts, decl_map))

    used_record_fields =
      if opts[:strip_dead_code] == false do
        nil
      else
        RecordFieldMacros.used_field_keys(decl_map, reachable_for_fields)
      end

    {_record_field_defines, record_field_macros} =
      RecordFieldMacros.definitions(ir, used_fields: used_record_fields)
    Process.put(:elmc_constructor_tags, constructor_tags)
    Process.put(:elmc_record_field_macros, record_field_macros)
    Process.put(:elmc_vector_resource_slots, IRQueries.pebble_vector_resource_slot_map(ir))
    Process.put(:elmc_bitmap_resource_slots, IRQueries.pebble_bitmap_resource_slot_map(ir))
    Process.put(:elmc_animation_resource_slots, IRQueries.pebble_animation_resource_slot_map(ir))
    Process.put(:elmc_font_resource_slots, IRQueries.pebble_font_resource_slot_map(ir))
    Process.put(:elmc_speaker_sample_resource_slots, IRQueries.pebble_speaker_sample_resource_slot_map(ir))
    Process.put(:elmc_enum_types, IRQueries.enum_type_set(ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))
    Process.put(:elmc_union_type_names, IRQueries.union_type_name_set(ir))

    schema_registry = SchemaRegistry.build(ir)
    Process.put(:elmc_schema_registry, schema_registry)

    entry_module = opts[:entry_module] || "Main"
    Process.put(:elmc_named_record_literals, opts[:named_record_literals] == true)

    msg_names =
      ir
      |> IRAnalysis.msg_constructors(entry_module)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    Process.put(:elmc_pebble_msg_names, msg_names)

    Process.put(
      :elmc_msg_constructor_payload_specs,
      IRAnalysis.msg_constructor_payload_specs(ir, entry_module)
    )

    decl_map = IRQueries.function_decl_map(ir)
    generic_targets = GenericTargets.function_targets(ir, opts)

    wrapper_targets =
      GenericTargets.wrapper_targets(
        ir,
        opts,
        decl_map,
        DirectRenderAnalysis.targets(ir, opts, decl_map)
      )

    direct_call_targets =
      generic_targets
      |> Enum.filter(fn target ->
        {mod, name} = target

        case Map.fetch(decl_map, target) do
          {:ok, decl} ->
            not MapSet.member?(wrapper_targets, target) and
              not NativeFunctionCall.native_scalar_fn?(decl, mod, decl_map) and
              not RcRequired.platform_worker_rc_abi?(mod, name, decl_map)

          :error ->
            false
        end
      end)
      |> MapSet.new()

    direct_command_targets = Host.direct_command_targets(ir, opts, decl_map)

    direct_emit_targets =
      if opts[:direct_render_only] == true do
        {_def_targets, emit_targets, _pruned} = DirectRenderAnalysis.target_sets(decl_map, opts)
        emit_targets
      else
        MapSet.new()
      end

    used_union_ctors =
      if opts[:strip_dead_code] == false do
        nil
      else
        MacroReachability.used_union_ctors(
          decl_map,
          generic_targets
          |> MapSet.union(direct_command_targets)
          |> MapSet.union(direct_emit_targets)
        )
        |> MapSet.union(SpecialValues.compiler_folded_union_constructors())
      end

    {_union_constructor_defines, union_constructor_macros} =
      UnionMacros.definitions(ir, used_union_ctors: used_union_ctors)

    _union_debug_ctor_fn =
      UnionMacros.debug_ctor_name_fn(ir,
        used_union_ctors: used_union_ctors,
        prod: Map.get(opts, :prod, false)
      )

    Process.put(:elmc_union_constructor_macros, union_constructor_macros)

    exported_targets = Analysis.exported_function_targets(decl_map, opts, direct_command_targets)

    Process.put(:elmc_wrapper_targets, wrapper_targets)
    Process.put(:elmc_direct_call_targets, direct_call_targets)
    Process.put(:elmc_native_boxed_rc_abi, %{})
    Process.put(:elmc_native_bool_rc_abi, %{})
    Process.put(:elmc_exported_targets, exported_targets)
    Process.put(:elmc_function_arities, function_arities)
    Process.put(:elmc_program_decls, decl_map)
    storage_plans = LayoutSolver.analyze(decl_map, schema_registry)
    Process.put(:elmc_storage_plans, storage_plans)

    Process.put(
      :elmc_layout_coercion_diagnostics,
      Elmc.Backend.CCodegen.LayoutCoerceEmit.collect_call_warnings(
        decl_map,
        storage_plans.param_plans
      )
    )

    Process.put(:elmc_codegen_opts, opts)
    Process.put(:elmc_plan_ir_mode, Map.get(opts, :plan_ir_mode, Elmc.Backend.Plan.Defaults.plan_ir_mode()))
    Process.put(:elmc_plan_primary_fallbacks, [])
    Process.put(:elmc_plan_primary_lowered_cache, %{})
    Process.put(:elmc_plan_native_returns, %{})
    Process.put(:elmc_plan_native_value_returns, MapSet.new())
    DefRegistry.reset()
    _ = RcRequired.run!(decl_map, rc_required_opts(opts, direct_command_targets))
    :ok
  end

  @spec with_emit_session(ElmEx.IR.t(), Types.codegen_opts(), (-> term())) :: term()
  def with_emit_session(ir, opts, fun) when is_function(fun, 0) do
    prepare_emit_session!(ir, opts)

    try do
      fun.()
    after
      reset_process_state!()
    end
  end

  @spec source(ElmEx.IR.t(), Types.codegen_opts()) :: String.t()
  def source(ir, opts) do
    prepare_emit_session!(ir, opts)

    try do
      source_without_session_setup(ir, opts)
    after
      reset_process_state!()
    end
  end

  defp source_without_session_setup(ir, opts) do
    generic_targets = GenericTargets.function_targets(ir, opts)
    decl_map = IRQueries.function_decl_map(ir)
    function_arities = Process.get(:elmc_function_arities)
    wrapper_targets = Process.get(:elmc_wrapper_targets)
    exported_targets = Process.get(:elmc_exported_targets)

    direct_command_targets = Host.direct_command_targets(ir, opts, decl_map)

    used_union_ctors =
      if opts[:strip_dead_code] == false do
        nil
      else
        direct_emit_targets =
          if opts[:direct_render_only] == true do
            {_def_targets, emit_targets, _pruned} = DirectRenderAnalysis.target_sets(decl_map, opts)
            emit_targets
          else
            MapSet.new()
          end

        MacroReachability.used_union_ctors(
          decl_map,
          generic_targets
          |> MapSet.union(direct_command_targets)
          |> MapSet.union(direct_emit_targets)
        )
        |> MapSet.union(SpecialValues.compiler_folded_union_constructors())
      end

    used_record_fields =
      if opts[:strip_dead_code] == false do
        nil
      else
        RecordFieldMacros.used_field_keys(
          decl_map,
          generic_targets
          |> MapSet.union(direct_command_targets)
        )
      end

    {record_field_defines, _record_field_macros} =
      RecordFieldMacros.definitions(ir, used_fields: used_record_fields)

    {union_constructor_defines, _union_constructor_macros} =
      UnionMacros.definitions(ir, used_union_ctors: used_union_ctors)

    union_debug_ctor_fn =
      UnionMacros.debug_ctor_name_fn(ir,
        used_union_ctors: used_union_ctors,
        prod: Map.get(opts, :prod, false)
      )

    generic_native_prototypes =
      FunctionEmit.generic_native_function_prototypes(ir, generic_targets, decl_map)

    FunctionEmit.prelower_plan_native_returns(ir, generic_targets, decl_map)

    generic_plan_projection_prototypes =
      FunctionEmit.generic_plan_native_projection_prototypes(ir, generic_targets, decl_map)

    generic_rc_native_fusion_prototypes =
      FunctionEmit.generic_rc_native_fusion_prototypes(ir, generic_targets, decl_map)

    generic_function_prototypes =
      FunctionEmit.generic_function_prototypes(
        ir,
        generic_targets,
        wrapper_targets,
        decl_map,
        exported_targets
      )

    function_defs =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(
          &(&1.kind == :function && MapSet.member?(generic_targets, {mod.name, &1.name}))
        )
        |> Enum.sort_by(fn decl ->
          if Tuple2CaseTable.recognized?(mod.name, decl.name, decl.expr),
            do: 0,
            else: 1
        end)
        |> Enum.map(fn decl ->
          c_name = Util.module_fn_name(mod.name, decl.name)
          emit_wrapper? = MapSet.member?(wrapper_targets, {mod.name, decl.name})

          FunctionEmit.emit_function_def(
            decl,
            mod.name,
            c_name,
            function_arities,
            decl_map,
            emit_wrapper?
          )
        end)
      end)
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    direct_command_defs = DirectRenderRegistry.defs(ir, opts)

    lambda_def_items =
      Process.get(:elmc_lambdas, [])
      |> Enum.reverse()

    lambda_defs =
      lambda_def_items
      |> dedupe_lambda_defs_by_name()
      |> prune_unreferenced_lambda_defs([function_defs, direct_command_defs])
      |> Enum.join("\n")

    trig_fallback_prelude =
      Emit.generated_trig_fallback_prelude([lambda_defs, function_defs, direct_command_defs])

    render_cmd_prelude =
      Emit.generated_render_cmd_prelude([lambda_defs, function_defs, direct_command_defs])

    magic_number_defines =
      Emit.generated_magic_number_defines(
        [lambda_defs, function_defs, direct_command_defs],
        opts
      )

    resource_slot_defines =
      Emit.generated_resource_slot_defines(
        [lambda_defs, function_defs, direct_command_defs],
        opts,
        ir
      )

    """
    #include "elmc_generated.h"
    #include "elmc_pebble.h"
    #include <stdbool.h>
    #include <stdio.h>
    #include <stdlib.h>

    #if defined(__GNUC__)
    #pragma GCC diagnostic ignored "-Wunused-function"
    #pragma GCC diagnostic ignored "-Wunused-variable"
    #endif

    #{union_constructor_defines}

    #{union_debug_ctor_fn}

    #{record_field_defines}

    #{resource_slot_defines}

    #{magic_number_defines}

    #{Emit.pebble_debug_probe_prelude(opts)}

    #{trig_fallback_prelude}

    #{render_cmd_prelude}

    #{generic_native_prototypes}

    #{generic_plan_projection_prototypes}

    #{generic_rc_native_fusion_prototypes}

    #{generic_function_prototypes}

    #{lambda_defs}

    #{function_defs}

    #{direct_scene_guard(direct_command_defs, opts, ir)}
    """
    |> finalize_source()
  end

  defp dedupe_lambda_defs_by_name(lambda_defs) when is_list(lambda_defs) do
    {deduped, _seen} =
      Enum.reduce(lambda_defs, {[], MapSet.new()}, fn defn, {acc, seen} ->
        case lambda_definition_name(defn) do
          name when is_binary(name) ->
            if MapSet.member?(seen, name) do
              {acc, seen}
            else
              {[defn | acc], MapSet.put(seen, name)}
            end

          _ ->
            {[defn | acc], seen}
        end
      end)

    Enum.reverse(deduped)
  end

  defp prune_unreferenced_lambda_defs([], _root_chunks), do: []

  defp prune_unreferenced_lambda_defs(lambda_defs, root_chunks) do
    by_name =
      lambda_defs
      |> Enum.map(fn defn -> {lambda_definition_name(defn), defn} end)
      |> Enum.reject(fn {name, _defn} -> is_nil(name) end)
      |> Map.new()

    roots =
      root_chunks
      |> referenced_lambda_names()
      |> MapSet.intersection(MapSet.new(Map.keys(by_name)))

    reachable_lambda_names(roots, by_name)
    |> then(fn reachable ->
      Enum.filter(lambda_defs, fn defn ->
        name = lambda_definition_name(defn)
        is_binary(name) and MapSet.member?(reachable, name)
      end)
    end)
  end

  defp reachable_lambda_names(roots, by_name) do
    Stream.iterate(roots, fn seen ->
      seen
      |> Enum.flat_map(fn name -> by_name |> Map.fetch!(name) |> referenced_lambda_names() end)
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(by_name)))
      |> MapSet.union(seen)
    end)
    |> Enum.reduce_while(MapSet.new(), fn seen, previous ->
      if MapSet.equal?(seen, previous), do: {:halt, seen}, else: {:cont, seen}
    end)
  end

  defp lambda_definition_name(defn) when is_binary(defn) do
    case Regex.run(lambda_symbol_regex(), defn) do
      [name] -> name
      _ -> nil
    end
  end

  defp referenced_lambda_names(chunks) when is_list(chunks) do
    chunks
    |> Enum.flat_map(&referenced_lambda_names/1)
    |> MapSet.new()
  end

  defp referenced_lambda_names(chunk) when is_binary(chunk) do
    lambda_symbol_regex()
    |> Regex.scan(chunk)
    |> Enum.map(fn [name] -> name end)
  end

  defp lambda_symbol_regex,
    do:
      ~r/\belmc_(?:(?:fn_[A-Za-z0-9_]+_closure_\d+)|(?:lambda|partial_ref|top_level_ref|partial_union)_\d+)\b/
end
