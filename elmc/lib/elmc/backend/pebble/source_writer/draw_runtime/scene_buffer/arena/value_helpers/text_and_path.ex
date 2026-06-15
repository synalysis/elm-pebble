defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ValueHelpers.TextAndPath do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
    static int elmc_scene_text_len(const ElmcPebbleDrawCmd *cmd) {
      int text_len = 0;
      if (!cmd) return 0;
      while (text_len < (int)sizeof(cmd->text) && cmd->text[text_len] != '\\0') text_len++;
      return text_len;
    }
    #endif

    static int elmc_scene_path_extra_size(const ElmcPebbleDrawCmd *cmd) {
      (void)cmd;
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      if (!cmd) return 0;
      if (cmd->kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
          cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
          cmd->kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN) {
        int count = cmd->path_point_count;
        if (count < 0) count = 0;
        if (count > 16) count = 16;
        return 7 + (count * 4);
      }
    #endif
      return 0;
    }

    """
  end
end
