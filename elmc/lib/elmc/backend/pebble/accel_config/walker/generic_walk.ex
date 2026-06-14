defmodule Elmc.Backend.Pebble.AccelConfig.Walker.GenericWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.{AccelConfig.Walker.KernelAccel, AccelConfig.Walker.PebbleAccel, Types}

  @spec reduce(Types.ir_walk_node(), Types.accel_config(), Types.record_literal_bindings()) ::
          Types.accel_config()
  def reduce(
        %{op: :qualified_call, target: "Pebble.Accel.onData", args: [_config | _]} = node,
        acc,
        bindings
      ) do
    PebbleAccel.reduce(node, acc, bindings)
  end

  def reduce(
        %{op: :qualified_call, target: "Elm.Kernel.PebbleWatch.onAccelData", args: [hz | _]} = node,
        acc,
        _bindings
      )
      when is_integer(hz) or is_map(hz) do
    KernelAccel.reduce(node, acc)
  end

  def reduce(%{} = node, acc, bindings) do
    reduce_children(node, acc, bindings)
  end

  def reduce(list, acc, bindings) when is_list(list),
    do: Enum.reduce(list, acc, &reduce(&1, &2, bindings))

  def reduce(_node, acc, _bindings), do: acc

  @spec reduce_children(
          Types.ir_map_node(),
          Types.accel_config(),
          Types.record_literal_bindings()
        ) :: Types.accel_config()
  defp reduce_children(node, acc, bindings) do
    node
    |> Map.values()
    |> Enum.reduce(acc, &reduce(&1, &2, bindings))
  end
end
