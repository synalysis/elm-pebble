defmodule Elmc.Backend.CCodegen.IntLiteralRef do
  @moduledoc false

  alias Elmc.Backend.CCodegen.ResourceSlotMacros
  alias Elmc.Backend.CCodegen.ResourceUnion
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.CCodegen.UnionMacros

  @spec ref(Types.ir_expr(), Types.compile_env()) :: String.t()
  def ref(%{op: :int_literal} = expr, env) do
    ResourceSlotMacros.literal_ref(expr) ||
      UnionMacros.literal_ref(expr, env) ||
      Integer.to_string(ResourceUnion.int_literal_value(expr))
  end

  def ref(%{op: :c_int_expr, value: value}, _env) when is_binary(value), do: value

  def ref(_expr, _env), do: "0"
end
