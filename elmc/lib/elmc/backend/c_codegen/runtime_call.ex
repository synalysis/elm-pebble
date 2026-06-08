defmodule Elmc.Backend.CCodegen.RuntimeCall do
  @moduledoc false

  alias Elmc.Backend.CCodegen.RuntimeCall.Core
  alias Elmc.Backend.CCodegen.RuntimeCall.Dispatcher
  alias Elmc.Backend.CCodegen.Types

  @spec flatten_append_ir(Types.ir_expr(), Types.ir_expr()) :: Types.ir_expr()
  defdelegate flatten_append_ir(left, right), to: Core

  @spec compile(Types.ir_runtime_call_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  defdelegate compile(expr, env, counter), to: Dispatcher

  @spec compile_int_sub_list_length(Types.ir_expr(), Types.ir_expr(), Types.compile_env(), Types.compile_counter()) ::
          {:ok, String.t(), String.t(), Types.compile_counter()} | :error
  defdelegate compile_int_sub_list_length(left, right, env, counter), to: Core
end
