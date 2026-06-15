defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.Fallbacks.PathFull do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if ((payload_len == ELMC_SCENE_PL_FULL && !elmc_scene_is_path_kind(kind)) ||
          (payload_len > ELMC_SCENE_PL_FULL && elmc_scene_is_path_kind(kind))) {
        rc = elmc_scene_read_full_i32s(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        if (elmc_scene_is_path_kind(kind)) {
          rc = elmc_scene_read_path_tail(bytes, offset, payload_end, out_cmd); if (rc != 0) return rc;
        }
        return 0;
      }
    """
  end
end
