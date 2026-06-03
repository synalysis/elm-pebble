defmodule Elmc.Backend.CCodegen.DirectRender.Registry do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias ElmEx.IR

  @spec decls(IR.t(), Types.codegen_opts()) :: String.t()
  def decls(%IR{} = ir, opts) do
    decl_map = IRQueries.function_decl_map(ir)

    ir
    |> Host.direct_command_targets(opts, decl_map)
    |> Enum.map(fn {module_name, decl_name} ->
      c_name = Util.module_fn_name(module_name, decl_name)
      macro = Util.direct_command_macro(module_name, decl_name)

      """
      #define #{macro} 1
      int #{c_name}_commands(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds);
      int #{c_name}_commands_from(ElmcValue ** const args, const int argc, void * const out_cmds, const int max_cmds, const int skip, int *out_emitted);
      """
    end)
    |> Enum.join("\n")
  end

  @spec defs(IR.t(), Types.codegen_opts()) :: String.t()
  def defs(%IR{} = ir, opts) do
    decl_map = IRQueries.function_decl_map(ir)
    {def_targets, emit_targets, pruned} = Host.direct_command_target_sets(decl_map, opts)

    if MapSet.size(def_targets) == 0 do
      ""
    else
      decls =
        ir.modules
        |> Enum.flat_map(fn mod ->
          mod.declarations
          |> Enum.filter(&(&1.kind == :function && MapSet.member?(def_targets, {mod.name, &1.name})))
          |> Enum.map(fn decl -> {mod, decl} end)
        end)

      prototypes =
        decls
        |> Enum.map_join("\n", fn {mod, decl} ->
          c_name = Util.module_fn_name(mod.name, decl.name)

          native_proto =
            if Host.native_direct_command_args?(decl) do
              "\nstatic int #{c_name}_commands_append_native(#{Host.native_direct_command_params(decl)}, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted);"
            else
              ""
            end

          "static int #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcGeneratedPebbleDrawCmd * const out_cmds, const int max_cmds, const int skip, int * const count, int * const emitted);#{native_proto}"
        end)

      defs =
        decls
        |> Enum.map_join("\n", fn {mod, decl} ->
          Host.direct_command_def(mod, decl, emit_targets, pruned, decl_map)
        end)

      prototypes <> "\n\n" <> defs
    end
  end

  @spec prelude(boolean()) :: String.t()
  def prelude(false), do: ""

  def prelude(true) do
    """
    #include "elmc_pebble.h"
    #include <string.h>

    typedef ElmcPebbleDrawCmd ElmcGeneratedPebbleDrawCmd;

    static void elmc_generated_draw_init(ElmcGeneratedPebbleDrawCmd *cmd, int64_t kind) {
      memset(cmd, 0, sizeof(*cmd));
      cmd->kind = kind;
    }
    """
  end
end
