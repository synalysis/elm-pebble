defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.PathProbes do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #ifndef ELMC_PEBBLE_DRAW_PATH_PROBES
    #define ELMC_PEBBLE_DRAW_PATH_PROBES 0
    #endif

    #define ELMC_DRAW_PATH_RENDER_MODEL_ENTER 0xED9A0101U
    #define ELMC_DRAW_PATH_RENDER_MODEL_EXIT 0xED9A8101U
    #define ELMC_DRAW_PATH_DRAW_UPDATE_ENTER 0xED9A0102U
    #define ELMC_DRAW_PATH_DRAW_UPDATE_EXIT 0xED9A8102U
    #define ELMC_DRAW_PATH_ENSURE_SCENE_ENTER 0xED9A0103U
    #define ELMC_DRAW_PATH_ENSURE_SCENE_EXIT 0xED9A8103U
    #define ELMC_DRAW_PATH_SCENE_NEXT_ENTER 0xED9A0104U
    #define ELMC_DRAW_PATH_SCENE_NEXT_EXIT 0xED9A8104U
    #define ELMC_DRAW_PATH_VIEW_APPEND_ENTER 0xED9A0105U
    #define ELMC_DRAW_PATH_VIEW_APPEND_EXIT 0xED9A8105U
    #define ELMC_DRAW_PATH_ELM_INIT_ENTER 0xED9A0106U
    #define ELMC_DRAW_PATH_ELM_INIT_EXIT 0xED9A8106U
    #define ELMC_DRAW_PATH_FONT_FOR_TEXT_ENTER 0xED9A0107U
    #define ELMC_DRAW_PATH_FONT_FOR_TEXT_EXIT 0xED9A8107U
    #define ELMC_DRAW_PATH_GRAPHICS_TEXT_ENTER 0xED9A0108U
    #define ELMC_DRAW_PATH_GRAPHICS_TEXT_EXIT 0xED9A8108U

    #if ELMC_PEBBLE_DRAW_PATH_PROBES && defined(ELMC_PEBBLE_PLATFORM)
    #include <data_logging.h>
    static inline void elmc_draw_path_probe(uint32_t tag) {
      DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
      if (session) {
        data_logging_finish(session);
      }
    }
    #define ELMC_DRAW_PATH_PROBE(tag) elmc_draw_path_probe((uint32_t)(tag))
    #else
    #define ELMC_DRAW_PATH_PROBE(tag) do { (void)(tag); } while (0)
    #endif

"""
  end
end
