defmodule Elmc.Backend.CCodegen.VarCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.FunctionCallCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.Types

  @spec compile(Types.ir_var_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :var, name: name}, env, counter) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [base, field] when field != "" ->
        Host.compile_expr(%{op: :field_access, arg: base, field: field}, env, counter)

      _ ->
        FunctionCallCompile.compile_var(name, env, counter)
    end
  end
end
