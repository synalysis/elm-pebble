defmodule Elmc.Backend.Pebble.AccelConfig.Walker.PebbleAccel do
  @moduledoc false

  alias Elmc.Backend.Pebble.{AccelConfig.Resolve, Types}

  @spec reduce(
          %{required(:op) => atom(), required(:target) => String.t(), required(:args) => list()},
          Types.accel_config(),
          Types.record_literal_bindings()
        ) :: Types.accel_config()
  def reduce(
        %{op: :qualified_call, target: "Pebble.Accel.onData", args: [config | _]},
        acc,
        bindings
      ) do
    resolved = Resolve.resolve_expr(config, bindings)

    acc
    |> Map.put(
      :samples_per_update,
      Resolve.int_field(resolved, "samplesPerUpdate", acc.samples_per_update)
    )
    |> Map.put(:sampling_hz, Resolve.sampling_hz(resolved, acc.sampling_hz))
  end

  def reduce(_node, acc, _bindings), do: acc
end