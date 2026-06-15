defmodule Elmc.Backend.Pebble.IRAnalysis.Msg.Constructors.PayloadSpecs do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.IRAnalysis.Msg.ModuleQuery
  alias Elmc.Backend.Pebble.Types

  @spec from_ir(IR.t(), Types.entry_module()) :: Types.msg_constructor_payload_specs()
  def from_ir(%IR{} = ir, entry_module) do
    case ModuleQuery.entry_msg_union(ir, entry_module) do
      nil ->
        %{}

      union ->
        union
        |> Map.get(:constructors, [])
        |> Map.new(fn constructor ->
          {Map.get(constructor, :name), Map.get(constructor, :arg)}
        end)
    end
  end
end
