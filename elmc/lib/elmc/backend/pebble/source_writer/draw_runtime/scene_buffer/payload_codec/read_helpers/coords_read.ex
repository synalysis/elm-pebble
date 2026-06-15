defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.CoordsRead do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_scene_read_coords_i16(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      out_cmd->p0 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p3 = elmc_scene_read_i16(bytes, offset, payload_end);
      return 0;
    }

    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
    static int elmc_scene_read_text_bounds_i16(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      out_cmd->p1 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p2 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p3 = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->p4 = elmc_scene_read_i16(bytes, offset, payload_end);
      return 0;
    }
    #endif

"""
  end
end
