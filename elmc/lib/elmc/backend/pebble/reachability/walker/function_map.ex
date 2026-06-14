defmodule Elmc.Backend.Pebble.Reachability.Walker.FunctionMap do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Types

  @spec from_ir(IR.t()) :: Types.reachability_function_map()
  def from_ir(%IR{} = ir) do
    ir.modules
    |> Enum.flat_map(fn mod ->
      mod.declarations
      |> Enum.filter(&(&1.kind == :function))
      |> Enum.map(fn decl -> {"#{mod.name}.#{decl.name}", {mod.name, decl.expr}} end)
    end)
    |> Map.new()
  end
end
