defmodule Elmc.Backend.Pebble.HeaderWriter.AccelDefaults do
  @moduledoc false

  alias Elmc.Backend.Pebble.HeaderWriter.Bindings

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.HeaderWriter.Bindings

  @spec body(Bindings.t()) :: Types.c_source()
  def body(%{} = bindings) do
    %{
      accel_samples_per_update: accel_samples_per_update,
      accel_sampling_hz: accel_sampling_hz
    } = bindings

    """
    #ifndef ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE
    #define ELMC_PEBBLE_ACCEL_SAMPLES_PER_UPDATE #{accel_samples_per_update}
    #endif
    #ifndef ELMC_PEBBLE_ACCEL_SAMPLING_HZ
    #define ELMC_PEBBLE_ACCEL_SAMPLING_HZ #{accel_sampling_hz}
    #endif
    """
  end
end
