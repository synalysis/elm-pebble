defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneQuery.SceneDecodeFrom do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end);

    static int elmc_pebble_scene_decode_from(
        ElmcPebbleApp *app,
        ElmcPebbleDrawCmd *out_cmds,
        int max_cmds,
        int skip,
        int *out_emitted_end) {
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
      return elmc_pebble_stream_view_cmds(app, out_cmds, max_cmds, skip, out_emitted_end);
    #else
      int byte_offset = 0;
      int emitted = 0;
      int count = 0;
      int rc = 0;
      while (byte_offset < app->scene.byte_count && count < max_cmds) {
        ElmcPebbleDrawCmd cmd;
        rc = elmc_pebble_scene_decode_record(
            app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd);
        if (rc != 0) return rc;
        if (emitted >= skip) {
          out_cmds[count++] = cmd;
        }
        emitted += 1;
      }
      if (out_emitted_end) *out_emitted_end = emitted;
      return count;
    #endif
    }

    """
  end
end
