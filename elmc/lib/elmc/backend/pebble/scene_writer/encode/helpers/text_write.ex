defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.TextWrite do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
        static int elmc_scene_writer_write_text_tail(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          if (!writer || !writer->app) return -1;
          int text_len = elmc_scene_text_len(cmd);
          int rc = elmc_scene_writer_put_u8(writer, (unsigned char)text_len);
          if (rc != 0) return rc;
          rc = elmc_pebble_scene_reserve(writer->app, text_len);
          if (rc != 0) return rc;
          for (int i = 0; i < text_len; i++) {
            unsigned char byte = (unsigned char)cmd->text[i];
            rc = elmc_pebble_scene_put_u8(writer->app, byte);
            if (rc != 0) return rc;
          }
          return 0;
        }
        #endif

    """
  end
end
