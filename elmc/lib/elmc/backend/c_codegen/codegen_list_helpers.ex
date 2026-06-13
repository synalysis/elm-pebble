defmodule Elmc.Backend.CCodegen.CodegenListHelpers do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ListLoopCodegen

  @type repeat_codegen :: {:inline, String.t(), String.t()}

  @spec repeat_codegen(String.t(), String.t(), pos_integer(), map()) :: repeat_codegen()
  def repeat_codegen(count_ref, value_ref, loop_id, env \\ %{}) do
    {code, out} = ListLoopCodegen.emit_repeat_inline_loop(count_ref, value_ref, loop_id, env)
    {:inline, code, out}
  end
end
