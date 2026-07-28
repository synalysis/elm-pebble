defmodule Elmc.Backend.CCodegen.DirectRender.Emit.BoxedOperand do
  @moduledoc false
  alias Elmc.Backend.CCodegen.Types, as: Types
  alias Elmc.Backend.CCodegen.DirectRender.Emit.Operand

  @spec compile(Types.ir_expr() | nil, Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(expr, env, counter) do
    env = Map.put_new(env, :__direct_render_emit__, true)
    Operand.compile(expr, env, counter)
  end
end
