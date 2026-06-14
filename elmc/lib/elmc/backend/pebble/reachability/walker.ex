defmodule Elmc.Backend.Pebble.Reachability.Walker do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.Reachability.Walker.{FunctionMap, Graph}
  alias Elmc.Backend.Pebble.Types

  @entry_roots ~w(init update subscriptions view main)

  @spec reachable_call_targets(IR.t(), Types.entry_module()) :: Types.call_target_set()
  def reachable_call_targets(%IR{} = ir, entry_module) do
    function_map = FunctionMap.from_ir(ir)

    roots =
      @entry_roots
      |> Enum.map(&"#{entry_module}.#{&1}")
      |> Enum.filter(&Map.has_key?(function_map, &1))

    Graph.traverse(function_map, MapSet.new(roots), roots, MapSet.new())
  end
end
