defmodule Elmc.Backend.CCodegen.CodegenListHelpers do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ListLoopCodegen

  @type repeat_codegen :: {:inline, String.t(), String.t()}

  @spec repeat_codegen(String.t(), String.t(), pos_integer(), map()) :: repeat_codegen()
  def repeat_codegen(count_ref, value_ref, loop_id, env \\ %{}) do
    {code, out} = ListLoopCodegen.emit_repeat_inline_loop(count_ref, value_ref, loop_id, env)
    {:inline, code, out}
  end

  @spec emit_immortal_zero_list(String.t(), String.t(), pos_integer()) :: String.t()
  def emit_immortal_zero_list(sym, out, count) when is_integer(count) and count > 0 do
    Elmc.Runtime.IntList.emit_immortal_zeros(sym, out, count)
  end

  @spec emit_zero_repeat_prelude(String.t(), pos_integer()) :: String.t()
  def emit_zero_repeat_prelude(sym, count) when is_integer(count) and count > 0 do
    """
    #{Elmc.Runtime.IntList.emit_immortal_static_prelude(sym, Enum.map_join(1..count, ", ", fn _ -> "0" end), count)}

    static ElmcValue *#{sym}_get(void) {
      return (ElmcValue *)&#{sym}_value;
    }
    """
    |> String.trim_trailing()
  end
end
