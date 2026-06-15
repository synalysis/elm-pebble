defmodule Elmc.Backend.CCodegen.DirectRender.Registry do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util
  alias ElmEx.IR

  @spec decls(IR.t(), Types.codegen_opts()) :: String.t()
  def decls(%IR{} = ir, opts) do
    alias Elmc.Backend.CCodegen.DirectRender.Emit.Catch

    decl_map = IRQueries.function_decl_map(ir)

    command_macros =
      ir
      |> Host.direct_command_targets(opts, decl_map)
      |> Enum.map(fn {module_name, decl_name} ->
        macro = Util.direct_command_macro(module_name, decl_name)

        """
        #define #{macro} 1
        """
      end)
      |> Enum.join("\n")

    if command_macros == "" do
      ""
    else
      Catch.header_macros() <> "\n" <> command_macros
    end
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
              "\nstatic RC #{c_name}_commands_append_native(#{Host.native_direct_command_params(decl)}, ElmcSceneWriter * const writer);"
            else
              ""
            end

          "static RC #{c_name}_commands_append(ElmcValue ** const args, const int argc, ElmcSceneWriter * const writer);#{native_proto}"
        end)

      defs =
        decls
        |> Enum.map_join("\n", fn {mod, decl} ->
          Host.direct_command_def(mod, decl, emit_targets, pruned, decl_map)
        end)

      prototypes <> "\n\n" <> defs
    end
  end

end
