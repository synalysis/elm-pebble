defmodule Elmc.Backend.Pebble.IRAnalysis.Msg.Constructors.Arities do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{IRAnalysis.Msg.ModuleQuery, Types, Util}

  @spec from_ir(IR.t(), Types.entry_module()) :: Types.msg_constructor_arities()
  def from_ir(%IR{} = ir, entry_module) do
    case ModuleQuery.entry_msg_union(ir, entry_module) do
      nil ->
        %{}

      union ->
        union
        |> Map.get(:constructors, [])
        |> Enum.reduce(%{}, fn constructor, acc ->
          name = Map.get(constructor, :name)
          spec = Map.get(constructor, :arg)

          if is_binary(name) and name != "" do
            Map.put(acc, name, Util.payload_arity_for_spec(spec))
          else
            acc
          end
        end)
    end
  end
end
