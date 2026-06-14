defmodule Elmc.Backend.Pebble.AccelConfig.Walker do
  @moduledoc false

  alias ElmEx.IR
  alias Elmc.Backend.Pebble.{AccelConfig.Resolve, AccelConfig.Walker.GenericWalk, Types}

  @default_accel_config %{samples_per_update: 1, sampling_hz: 25}

  @spec default_accel_config() :: Types.accel_config()
  def default_accel_config, do: @default_accel_config

  @spec from_ir(IR.t(), Types.entry_module()) :: Types.accel_config()
  def from_ir(%IR{} = ir, _entry_module) do
    bindings = Resolve.bindings_from_ir(ir)

    ir.modules
    |> Enum.flat_map(fn mod -> Map.get(mod, :declarations, []) end)
    |> Enum.reduce(@default_accel_config, fn declaration, acc ->
      GenericWalk.reduce(
        Map.get(declaration, :expr) || Map.get(declaration, :body),
        acc,
        bindings
      )
    end)
  end
end
