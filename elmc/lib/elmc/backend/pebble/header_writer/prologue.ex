defmodule Elmc.Backend.Pebble.HeaderWriter.Prologue do
  @moduledoc false

  alias Elmc.Backend.Pebble.HeaderWriter.Bindings

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.HeaderWriter.Bindings

  @spec body(Bindings.t()) :: Types.c_source()
  def body(%{} = bindings) do
    %{
      scene_writer_early: scene_writer_early,
      feature_macros: feature_macros
    } = bindings

    """
    #ifndef ELMC_PEBBLE_H
    #define ELMC_PEBBLE_H

    #{scene_writer_early}

    #include "elmc_worker.h"

    #{feature_macros}
    """
  end
end
