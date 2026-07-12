defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.SceneDecode do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if !ELMC_PEBBLE_SCENE_STREAM_CMDS
    #{body_without_guard()}
    #endif
    """
  end

  defp body_without_guard do
    """
    int elmc_pebble_scene_decode_record(
        const unsigned char *bytes,
        int byte_count,
        int *offset,
        ElmcPebbleDrawCmd *out_cmd) {
      if (!bytes || !offset || !out_cmd || *offset + 2 > byte_count) return -1;
      int kind = bytes[*offset];
      int payload_len = bytes[*offset + 1];
      *offset += 2;
      int payload_end = *offset + payload_len;
      if (payload_end > byte_count) return -2;
      elmc_draw_cmd_init(out_cmd, kind);
      int rc = elmc_pebble_scene_decode_payload(kind, payload_len, bytes, offset, payload_end, out_cmd);
      if (rc != 0) return rc;
      *offset = payload_end;
      return 0;
    }
    """
  end
end
