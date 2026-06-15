defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.Preamble do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (!cmd) return -1;
      int32_t kind = cmd->kind;
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      int text_len = elmc_scene_text_len(cmd);
    #endif

    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      if (kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
          kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
          kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
        return ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd);
      }
    #endif

"""
  end
end
