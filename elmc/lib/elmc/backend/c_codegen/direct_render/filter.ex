defmodule Elmc.Backend.CCodegen.DirectRender.Filter do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @spec filter(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: MapSet.t(Types.function_decl_key())
  def filter(targets, decl_map) do
    filtered = filter_once(targets, decl_map)

    if MapSet.equal?(filtered, targets) do
      filtered
    else
      filter(filtered, decl_map)
    end
  end

  @spec filter_once(
          MapSet.t(Types.function_decl_key()),
          Types.function_decl_map()
        ) :: MapSet.t(Types.function_decl_key())
  defp filter_once(targets, decl_map) do
    Enum.reduce(targets, MapSet.new(), fn {module_name, _decl_name} = target, acc ->
      decl = Map.fetch!(decl_map, target)

      if Host.direct_supported?(decl.expr, module_name, decl_map, MapSet.new()) do
        Elmc.Backend.CCodegen.GeneratedSource.reset_emit_probe_state!()

        # Use the full candidate set (not just targets validated earlier in this pass)
        # so mutually dependent direct helpers (e.g. drawDial calling drawOuterScale)
        # can be checked in one fixed-point round.
        env = Host.direct_emit_check_env(decl, module_name, targets, decl_map)

        case Host.direct_emit_expr(decl.expr, env, 0) do
          {:ok, _code, _counter} -> MapSet.put(acc, target)
          :error -> acc
        end
      else
        acc
      end
    end)
  end
end
