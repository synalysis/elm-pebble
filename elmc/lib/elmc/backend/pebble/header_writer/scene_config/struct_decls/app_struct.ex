defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.AppStruct do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    typedef struct ElmcPebbleApp {
      ElmcWorkerState worker;
      int initialized;
      int run_mode;
      int has_prev_ui;
      int64_t prev_window_id;
      int64_t prev_layer_id;
      uint64_t prev_ops_hash;
      ElmcValue *stream_view_result;
      ElmcPebbleSceneBuffer scene;
    #if ELMC_PEBBLE_SCENE_CACHE_ENABLED
      int scene_draw_byte_offset;
    #endif
    #if ELMC_PEBBLE_DIRTY_REGION_ENABLED
      ElmcPebbleSceneBuffer prev_scene;
      ElmcPebbleRect dirty_rect;
      int dirty_rect_valid;
      int dirty_rect_full;
    #endif
    } ElmcPebbleApp;

    """
  end
end
