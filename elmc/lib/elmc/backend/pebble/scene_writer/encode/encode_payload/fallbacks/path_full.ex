defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.Fallbacks.PathFull do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_PATH
          if (elmc_scene_is_path_kind(cmd->kind) &&
              payload_len == ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd)) {
            rc = elmc_scene_writer_write_full_i32s(writer, cmd); if (rc != 0) return rc;
            rc = elmc_scene_writer_write_path_tail(writer, cmd); if (rc != 0) return rc;
            return 0;
          }
        #endif
        #if ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT || ELMC_PEBBLE_FEATURE_DRAW_ARC || ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL || ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT || ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT || ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT || ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT || ELMC_PEBBLE_FEATURE_DRAW_ROTATED_BITMAP || ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL || ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
          if (payload_len == ELMC_SCENE_PL_FULL && !elmc_scene_is_path_kind(cmd->kind)) {
            rc = elmc_scene_writer_write_full_i32s(writer, cmd); if (rc != 0) return rc;
            return 0;
          }
        #endif
    """
  end
end
