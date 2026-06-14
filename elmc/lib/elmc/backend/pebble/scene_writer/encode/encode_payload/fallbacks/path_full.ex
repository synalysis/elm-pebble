defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.Fallbacks.PathFull do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          if (payload_len >= ELMC_SCENE_PL_FULL &&
              (!elmc_scene_is_path_kind(cmd->kind) ||
               payload_len == ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd))) {
            rc = elmc_scene_writer_write_full_i32s(writer, cmd); if (rc != 0) return rc;
            if (elmc_scene_is_path_kind(cmd->kind) && payload_len > ELMC_SCENE_PL_FULL) {
              rc = elmc_scene_writer_write_path_tail(writer, cmd); if (rc != 0) return rc;
            }
            return 0;
          }
    """
  end
end
