defmodule Elmc.Backend.Pebble.HeaderWriter.Prologue do
  @moduledoc false

  alias Elmc.Backend.Pebble.HeaderWriter.Bindings
  alias Elmc.Backend.Pebble.Types

  @spec body(Bindings.t()) :: Types.c_source()
  def body(%{} = bindings) do
    %{
      scene_writer_early: scene_writer_early,
      feature_macros: feature_macros,
      aplite_direct_view_scene?: aplite_direct_view_scene?
    } = bindings

    aplite_direct_view =
      if aplite_direct_view_scene? do
        "#define ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE 1\n"
      else
        ""
      end

    """
    #ifndef ELMC_PEBBLE_H
    #define ELMC_PEBBLE_H

    #{aplite_direct_view}#{scene_writer_early}

    #include "elmc_worker.h"

    #{feature_macros}
    """
  end
end
