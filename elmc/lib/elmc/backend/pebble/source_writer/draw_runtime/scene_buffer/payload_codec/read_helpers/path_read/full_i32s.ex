defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.PathRead.FullI32s do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_scene_read_full_i32s(
        const unsigned char *bytes,
        int *offset,
        int payload_end,
        ElmcPebbleDrawCmd *out_cmd) {
      out_cmd->p0 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      out_cmd->p1 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      out_cmd->p2 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      out_cmd->p3 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      out_cmd->p4 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      out_cmd->p5 = elmc_pebble_scene_read_i32(bytes, offset, payload_end);
      return 0;
    }

    """
  end
end
