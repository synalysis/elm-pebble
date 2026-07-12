defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.SceneLog do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if defined(ELMC_PEBBLE_PLATFORM) && (ELMC_PEBBLE_DEBUG_LOGS || ELMC_PEBBLE_EMULATOR_STORAGE_LOGS)
    #define ELMC_PEBBLE_SCENE_LOG(...) APP_LOG(APP_LOG_LEVEL_INFO, __VA_ARGS__)
    #else
    #define ELMC_PEBBLE_SCENE_LOG(...) do { } while (0)
    #endif

    """
  end
end
