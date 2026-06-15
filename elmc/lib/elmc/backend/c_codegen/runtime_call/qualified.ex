defmodule Elmc.Backend.CCodegen.RuntimeCall.Qualified do
  @moduledoc false

  alias Elmc.Backend.CCodegen.RuntimeCall.Core
  alias Elmc.Backend.CCodegen.Types

  @spec compile(Types.ir_runtime_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  defdelegate compile(expr, env, counter), to: Core
end
