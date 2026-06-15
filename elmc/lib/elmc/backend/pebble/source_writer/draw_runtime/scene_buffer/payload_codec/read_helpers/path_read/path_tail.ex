defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.PathRead.PathTail do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_scene_read_path_tail(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      if (*offset >= payload_end) return 0;
      int count = bytes[*offset];
      *offset += 1;
      if (count < 0) count = 0;
      if (count > 16) count = 16;
      out_cmd->path_point_count = count;
      out_cmd->path_offset_x = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->path_offset_y = elmc_scene_read_i16(bytes, offset, payload_end);
      out_cmd->path_rotation = elmc_scene_read_i16(bytes, offset, payload_end);
      for (int i = 0; i < count; i++) {
        out_cmd->path_x[i] = (int16_t)elmc_scene_read_i16(bytes, offset, payload_end);
        out_cmd->path_y[i] = (int16_t)elmc_scene_read_i16(bytes, offset, payload_end);
      }
      return 0;
    #else
      (void)bytes;
      (void)offset;
      (void)payload_end;
      (void)out_cmd;
      return 0;
    #endif
    }
    """
  end
end
