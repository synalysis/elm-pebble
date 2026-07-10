defmodule Elmc.Backend.CCodegen.DirectRender.Emit.Env do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @spec check_env(
          Types.function_declaration(),
          String.t(),
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: Types.compile_env()
  def check_env(decl, module_name, direct_targets, decl_map) do
    arg_bindings = Host.c_arg_bindings(decl.args || [])

    arg_bindings
    |> Enum.reduce(
      %{
        __module__: module_name,
        __direct_targets__: direct_targets,
        __program_decls__: decl_map,
        __direct_pruned__: MapSet.new(),
        __record_alias_shapes__: record_alias_shapes()
      },
      fn {source_arg, c_arg, _index}, env ->
        Map.put(env, source_arg, c_arg)
      end
    )
    |> Host.put_typed_arg_bindings(arg_bindings, decl.type)
  end

  defp record_alias_shapes do
    case Process.get(:elmc_record_alias_shapes) do
      shapes when is_map(shapes) -> shapes
      _ -> %{}
    end
  end
end
