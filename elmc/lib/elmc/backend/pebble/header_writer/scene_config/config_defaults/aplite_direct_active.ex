defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.ApliteDirectActive do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    /* Dual-target headers may define ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE for codegen,
       but aplite-only scene settings apply only when building the aplite binary. */
    #ifndef ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE
    #if defined(ELMC_PEBBLE_APLITE_DIRECT_VIEW_SCENE) && defined(PBL_PLATFORM_APLITE)
    #define ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE 1
    #else
    #define ELMC_PEBBLE_APLITE_DIRECT_VIEW_ACTIVE 0
    #endif
    #endif

    """
  end
end
