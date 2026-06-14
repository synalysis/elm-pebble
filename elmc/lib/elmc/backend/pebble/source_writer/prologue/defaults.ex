defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.Defaults do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_AGENT_PROBES
    #define ELMC_AGENT_PROBES 0
    #endif

    #ifndef ELMC_PEBBLE_DIRTY_REGION_ENABLED
    #if defined(ELMC_PEBBLE_PLATFORM)
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 0
    #else
    #define ELMC_PEBBLE_DIRTY_REGION_ENABLED 1
    #endif
    #endif
"""
  end
end
