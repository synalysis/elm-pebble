defmodule Elmc.Backend.CCodegen.PerModuleArtifacts do
  @moduledoc false

  alias Elmc.Backend.CCodegen.CSource
  alias Elmc.Backend.CCodegen.Emit
  alias Elmc.Backend.CCodegen.FunctionEmit
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.Util

  @spec write_headers(ElmEx.IR.t(), String.t()) :: :ok | {:error, Types.file_error()}
  def write_headers(ir, c_dir) do
    Enum.reduce_while(ir.modules, :ok, fn mod, :ok ->
      safe_name = mod.name |> String.replace(".", "_")
      filename = "elmc_#{safe_name}.h"
      content = module_header(mod)

      case File.write(Path.join(c_dir, filename), content) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec write_sources(ElmEx.IR.t(), String.t()) :: :ok | {:error, Types.file_error()}
  def write_sources(ir, c_dir) do
    Enum.reduce_while(ir.modules, :ok, fn mod, :ok ->
      safe_name = mod.name |> String.replace(".", "_")
      filename = "elmc_#{safe_name}.c"
      content = module_source(mod)

      case File.write(Path.join(c_dir, filename), content) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @spec link_manifest(ElmEx.IR.t()) :: String.t()
  def link_manifest(ir) do
    modules =
      ir.modules
      |> Enum.map(fn mod ->
        safe_name = mod.name |> String.replace(".", "_")

        functions =
          mod.declarations
          |> Enum.filter(&(&1.kind == :function))
          |> Enum.map(fn decl ->
            %{
              "name" => decl.name,
              "c_symbol" => Util.module_fn_name(mod.name, decl.name),
              "arity" => length(decl.args || [])
            }
          end)

        %{
          "module" => mod.name,
          "header" => "c/elmc_#{safe_name}.h",
          "source" => "c/elmc_#{safe_name}.c",
          "functions" => functions,
          "imports" => mod.imports || []
        }
      end)

    Jason.encode!(%{"modules" => modules, "version" => "1.0"}, pretty: true)
  end

  @spec module_header(ElmEx.IR.Module.t()) :: String.t()
  defp module_header(mod) do
    safe_name = mod.name |> String.replace(".", "_") |> String.upcase()

    function_decls =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        "ElmcValue *#{c_name}(ElmcValue ** const args, const int argc);"
      end)
      |> Enum.join("\n")

    """
    #ifndef ELMC_#{safe_name}_H
    #define ELMC_#{safe_name}_H

    #include "../runtime/elmc_runtime.h"

    #{function_decls}

    #endif
    """
  end

  @spec module_source(ElmEx.IR.Module.t()) :: String.t()
  defp module_source(mod) do
    safe_name = mod.name |> String.replace(".", "_")

    function_defs =
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl ->
        c_name = Util.module_fn_name(mod.name, decl.name)
        {prelude, body} = FunctionEmit.emit_body(decl, mod.name)

        """
        #{prelude}#{if prelude == "", do: "", else: "\n"}
        ElmcValue *#{c_name}(ElmcValue ** const args, const int argc) {
          /* Ownership policy: #{Enum.join(decl.ownership, ", ")} */
          #{body}
        }
        """
      end)
      |> Enum.join("\n")

    """
    #include "elmc_#{safe_name}.h"
    #include "elmc_generated.h"

    #{Emit.pebble_debug_probe_prelude()}

    #{function_defs}
    """
    |> CSource.format()
  end
end
