defmodule Elmc.Backend.Pebble.IRAnalysis.Msg.Constructors.Tags do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.IRAnalysis.Msg.ModuleQuery
  alias Elmc.Backend.Pebble.Types

  @spec from_ir(IR.t(), Types.entry_module()) :: Types.msg_constructor_list()
  def from_ir(%IR{} = ir, entry_module) do
    case ModuleQuery.entry_msg_union(ir, entry_module) do
      nil ->
        []

      union ->
        union.tags
        |> Map.to_list()
        |> Enum.sort_by(fn {_name, tag} -> tag end)
    end
  end
end
