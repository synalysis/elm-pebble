defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ApliteDirectActive do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    /* Formerly enabled a separate aplite path (512B static scene, CACHE=0, sync
       ensure on the draw stack). Aplite now uses the same deferred malloc-backed
       scene cache as other platforms — keep ACTIVE=0 so one control-flow path
       is maintained. ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE remains a codegen flag
       for dual-target headers / direct encode, not a runtime scene-cache split. */
    #ifndef ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
    #define ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE 0
    #endif

    """
  end
end
