defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.Includes do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #include <time.h>
    #include <stdlib.h>
    #include <stdio.h>
    #include <string.h>
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
    #define ELMC_PEBBLE_PLATFORM 1
    #endif
    #ifdef ELMC_PEBBLE_PLATFORM
    #include <pebble.h>
    #if defined(__has_include)
    #if __has_include("../../elmc_emulator_build_flags.h")
    #include "../../elmc_emulator_build_flags.h"
    #elif __has_include("elmc_emulator_build_flags.h")
    #include "elmc_emulator_build_flags.h"
    #endif
    #endif
    #ifndef ELMC_PEBBLE_DEBUG_LOGS
    #define ELMC_PEBBLE_DEBUG_LOGS 0
    #endif
    #endif
    #ifndef ELMC_PEBBLE_HEAP_LOG
    #define ELMC_PEBBLE_HEAP_LOG 0
    #endif
    #include "elmc_pebble.h"

    """
  end
end
