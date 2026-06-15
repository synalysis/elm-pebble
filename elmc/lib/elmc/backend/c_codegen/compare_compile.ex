defmodule Elmc.Backend.CCodegen.CompareCompile do
  @moduledoc false

  alias Elmc.Backend.CCodegen.BuiltinOperators
  alias Elmc.Backend.CCodegen.Types

  @spec compile(
          Types.compare_kind(),
          Types.ir_expr(),
          Types.ir_expr(),
          Types.compile_env(),
          Types.compile_counter()
        ) :: Types.compile_result()
  @spec compile(Types.ir_compare_expr(), Types.compile_env(), Types.compile_counter()) ::
          Types.compile_result()
  def compile(%{op: :compare, kind: kind, left: left, right: right}, env, counter),
    do: compile(kind, left, right, env, counter)

  def compile(kind, left, right, env, counter) do
    operator =
      case kind do
        :eq -> "__eq__"
        :neq -> "__neq__"
        :gt -> "__gt__"
        :gte -> "__gte__"
        :lt -> "__lt__"
        :lte -> "__lte__"
        _ -> "__eq__"
      end

    BuiltinOperators.compare_operator(left, right, operator, env, counter)
  end
end
