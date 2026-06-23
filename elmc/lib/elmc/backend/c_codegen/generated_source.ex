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
  alias Elmc.Backend.CCodegen.MacroReachability
  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.RcRequired
  alias Elmc.Backend.CCodegen.RecordFieldMacros
  alias Elmc.Backend.CCodegen.SpecialValues
  alias Elmc.Backend.CCodegen.UnionMacros
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Pebble.IRAnalysis

  defp finalize_source(source), do: CSource.format(source)

  # Direct scene helpers are linked for every Pebble platform, including aplite.
  defp direct_scene_guard(content, _opts, _ir) when is_binary(content) do
    String.trim_trailing(content)
  end

  @spec header(ElmEx.IR.t(), Types.codegen_opts()) :: String.t()
  def header(ir, opts) do
    direct_cmd_decls = DirectRenderRegistry.decls(ir, opts)
    decl_map = IRQueries.function_decl_map(ir)
    _ = RcRequired.run!(decl_map, opts)
    wrapper_targets = GenericTargets.wrapper_targets(ir, opts)
    direct_command_targets = Host.direct_command_targets(ir, opts, decl_map)
    exported_targets = Analysis.exported_function_targets(decl_map, opts, direct_command_targets)

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
    |> tap(fn _ -> Process.delete(:elmc_rc_required) end)
  end

  @spec source(ElmEx.IR.t(), Types.codegen_opts()) :: String.t()
  def source(ir, opts) do
    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_lambda_counter, 0)
    Process.put(:elmc_lambda_defs, %{})
    Process.put(:elmc_borrowed_field_refs, MapSet.new())

    function_arities =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, length(decl.args || [])} end)
      end)
      |> Map.new()

    constructor_tags = IRQueries.constructor_tag_map(ir)
    {record_field_defines, record_field_macros} = RecordFieldMacros.definitions(ir)
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

    entry_module = opts[:entry_module] || "Main"
    Process.put(:elmc_named_record_literals, opts[:named_record_literals] == true)

    msg_names =
      ir
      |> IRAnalysis.msg_constructors(entry_module)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    Process.put(:elmc_pebble_msg_names, msg_names)

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
        case Map.fetch(decl_map, target) do
          {:ok, decl} ->
            not MapSet.member?(wrapper_targets, target) and
              not NativeFunctionCall.native_scalar_fn?(decl, elem(target, 0), decl_map)

          :error ->
            false
        end
      end)
      |> MapSet.new()

    direct_command_targets = Host.direct_command_targets(ir, opts, decl_map)

    used_union_ctors =
      if opts[:strip_dead_code] == false do
        nil
      else
        MacroReachability.used_union_ctors(
          decl_map,
          MapSet.union(generic_targets, direct_command_targets)
        )
        |> MapSet.union(SpecialValues.compiler_folded_union_constructors())
      end

    {union_constructor_defines, union_constructor_macros} =
      UnionMacros.definitions(ir, used_union_ctors: used_union_ctors)

    union_debug_ctor_fn =
      UnionMacros.debug_ctor_name_fn(ir,
        used_union_ctors: used_union_ctors,
        prod: Map.get(opts, :prod, false)
      )

    Process.put(:elmc_union_constructor_macros, union_constructor_macros)

    exported_targets = Analysis.exported_function_targets(decl_map, opts, direct_command_targets)

    Process.put(:elmc_direct_call_targets, direct_call_targets)
    Process.put(:elmc_exported_targets, exported_targets)
    Process.put(:elmc_function_arities, function_arities)
    Process.put(:elmc_program_decls, decl_map)
    Process.put(:elmc_codegen_opts, opts)
    _ = RcRequired.run!(decl_map, opts)

    generic_native_prototypes =
      FunctionEmit.generic_native_function_prototypes(ir, generic_targets, decl_map)

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
          if match?({:ok, _, _}, Tuple2CaseTable.try_emit(mod.name, decl.name, decl.expr)),
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
      |> prune_unreferenced_lambda_defs([function_defs, direct_command_defs])
      |> Enum.join("\n")

    Process.delete(:elmc_lambdas)
    Process.delete(:elmc_direct_call_targets)
    Process.delete(:elmc_exported_targets)
    Process.delete(:elmc_function_arities)
    Process.delete(:elmc_program_decls)
    Process.delete(:elmc_codegen_opts)
    Process.delete(:elmc_rc_required)
    Process.delete(:elmc_lambda_counter)
    Process.delete(:elmc_lambda_defs)
    Process.delete(:elmc_constructor_tags)
    Process.delete(:elmc_union_constructor_macros)
    Process.delete(:elmc_record_field_macros)
    Process.delete(:elmc_subexpr_record_meta)
    Process.delete(:elmc_borrowed_field_refs)
    Process.delete(:elmc_pebble_msg_names)
    Process.delete(:elmc_vector_resource_slots)
    Process.delete(:elmc_bitmap_resource_slots)
    Process.delete(:elmc_animation_resource_slots)
    Process.delete(:elmc_font_resource_slots)
    Process.delete(:elmc_speaker_sample_resource_slots)
    Process.delete(:elmc_enum_types)
    Process.delete(:elmc_named_record_literals)

    trig_fallback_prelude =
      Emit.generated_trig_fallback_prelude([lambda_defs, function_defs, direct_command_defs])

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

    #{generic_native_prototypes}

    #{generic_function_prototypes}

    #{lambda_defs}

    #{function_defs}

    #{direct_scene_guard(direct_command_defs, opts, ir)}
    """
    |> finalize_source()
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
    do: ~r/\belmc_(?:lambda|partial_ref|top_level_ref|partial_union)_\d+\b/
end
