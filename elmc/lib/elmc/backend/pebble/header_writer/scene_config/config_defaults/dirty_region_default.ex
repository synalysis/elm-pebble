defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.ConfigDefaults.DirtyRegionDefault do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
    #else
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
    #endif
    #endif

    """
  end
end
