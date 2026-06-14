defmodule Elmc.Backend.Pebble.AccelConfig.Walker.KernelAccel do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec reduce(
          %{required(:op) => atom(), required(:target) => String.t(), required(:args) => list()},
          Types.accel_config()
        ) :: Types.accel_config()
  def reduce(
        %{op: :qualified_call, target: "Elm.Kernel.PebbleWatch.onAccelData", args: [hz | _]},
        acc
      )
      when is_integer(hz) or is_map(hz) do
    case hz do
      %{op: :int_literal, value: value} when is_integer(value) ->
        Map.put(acc, :sampling_hz, value)

      _ ->
        acc
    end
  end

  def reduce(_node, acc), do: acc
end
