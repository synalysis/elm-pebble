defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.RectUtils.NextRecord do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    static int elmc_pebble_scene_next_record(
        const unsigned char *bytes,
        int byte_count,
        int *offset,
        const unsigned char **out_record,
        int *out_record_len,
        ElmcPebbleDrawCmd *out_cmd) {
      if (!bytes || !offset || !out_record || !out_record_len || !out_cmd) return -1;
      if (*offset >= byte_count) return 1;
      if (*offset + 2 > byte_count) return -2;
      int start = *offset;
      int payload_len = bytes[start + 1];
      int record_len = 2 + payload_len;
      if (start + record_len > byte_count) return -3;
      int decode_offset = start;
      int rc = elmc_pebble_scene_decode_record(bytes, byte_count, &decode_offset, out_cmd);
      if (rc != 0) return rc;
      *out_record = bytes + start;
      *out_record_len = record_len;
      *offset = start + record_len;
      return 0;
    }
    #endif

    """
  end
end
