defmodule Elmc.Backend.CCodegen.GeneratedSource do
  @moduledoc false

  alias Elmc.Backend.CCodegen.DirectRender.Analysis, as: DirectRenderAnalysis
  alias Elmc.Backend.CCodegen.DirectRender.GenericTargets
  alias Elmc.Backend.CCodegen.DirectRender.Registry, as: DirectRenderRegistry
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Tuple2CaseTable
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias Elmc.Backend.Pebble.IRAnalysis

  defp finalize_source(source) do
    source |> Util.collapse_extra_newlines() |> String.trim_trailing() |> Kernel.<>("\n")
  end

  @spec header(ElmEx.IR.t(), Types.codegen_opts()) :: String.t()
  def header(ir, opts) do
    direct_cmd_decls = DirectRenderRegistry.decls(ir, opts)
    decl_map = IRQueries.function_decl_map(ir)
    generic_targets = GenericTargets.function_targets(ir, opts)
    wrapper_targets = GenericTargets.wrapper_targets(ir, opts)

    function_decls =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(fn decl ->
          target = {mod.name, decl.name}

          decl.kind == :function &&
            MapSet.member?(generic_targets, target) &&
            (MapSet.member?(wrapper_targets, target) ||
               not NativeFunctionCall.native_args?(decl, mod.name, decl_map))
        end)
        |> Enum.map(fn decl ->
          c_name = Util.module_fn_name(mod.name, decl.name)
          "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"
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
  end

  @spec source(ElmEx.IR.t(), Types.codegen_opts()) :: String.t()
  def source(ir, opts) do
    Process.put(:elmc_lambdas, [])
    Process.put(:elmc_lambda_counter, 0)
    Process.put(:elmc_lambda_defs, %{})

    function_arities =
      ir.modules
      |> Enum.flat_map(fn mod ->
        mod.declarations
        |> Enum.filter(&(&1.kind == :function))
        |> Enum.map(fn decl -> {{mod.name, decl.name}, length(decl.args || [])} end)
      end)
      |> Map.new()

    constructor_tags = IRQueries.constructor_tag_map(ir)
    Process.put(:elmc_constructor_tags, constructor_tags)
    Process.put(:elmc_vector_resource_slots, IRQueries.pebble_vector_resource_slot_map(ir))
    Process.put(:elmc_bitmap_resource_slots, IRQueries.pebble_bitmap_resource_slot_map(ir))
    Process.put(:elmc_animation_resource_slots, IRQueries.pebble_animation_resource_slot_map(ir))
    Process.put(:elmc_font_resource_slots, IRQueries.pebble_font_resource_slot_map(ir))
    Process.put(:elmc_enum_types, IRQueries.enum_type_set(ir))
    Process.put(:elmc_record_alias_shapes, IRQueries.record_alias_shape_map(ir))
    Process.put(:elmc_record_field_types, IRQueries.record_alias_field_types_map(ir))

    entry_module = opts[:entry_module] || "Main"

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

    generic_native_prototypes =
      FunctionEmit.generic_native_function_prototypes(ir, generic_targets, decl_map)

    generic_function_prototypes =
      FunctionEmit.generic_function_prototypes(ir, generic_targets, wrapper_targets, decl_map)

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

    lambda_defs =
      Process.get(:elmc_lambdas, [])
      |> Enum.reverse()
      |> Enum.join("\n")

    Process.delete(:elmc_lambdas)
    Process.delete(:elmc_lambda_counter)
    Process.delete(:elmc_lambda_defs)
    Process.delete(:elmc_constructor_tags)
    Process.delete(:elmc_pebble_msg_names)
    Process.delete(:elmc_vector_resource_slots)
    Process.delete(:elmc_bitmap_resource_slots)
    Process.delete(:elmc_animation_resource_slots)
    Process.delete(:elmc_font_resource_slots)
    Process.delete(:elmc_enum_types)

    trig_fallback_prelude =
      Emit.generated_trig_fallback_prelude([lambda_defs, function_defs, direct_command_defs])

    """
    #include "elmc_generated.h"
    #include "elmc_pebble.h"
    #include <stdio.h>

    #if defined(__GNUC__)
    #pragma GCC diagnostic ignored "-Wunused-function"
    #endif

    #{Emit.generated_magic_number_defines()}

    #{Emit.pebble_debug_probe_prelude()}

    #{trig_fallback_prelude}

    #{generic_native_prototypes}

    #{generic_function_prototypes}

    #{lambda_defs}

    #{function_defs}

    #{direct_command_defs}
    """
    |> finalize_source()
  end
end
