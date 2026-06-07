defmodule Elmc.Backend.CCodegen.FusedNativeReachability do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.Types

  @type function_decl_key :: Types.function_decl_key()

  @spec callees(String.t(), String.t(), map() | nil, map()) :: [function_decl_key()] | nil
  def callees(module_name, name, expr, decl_map) do
    Fusion.runtime_callees(module_name, name, expr, decl_map)
  end
end
