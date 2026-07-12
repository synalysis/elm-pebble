defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.StreamViewCmds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.c_symbol()) :: Types.c_source()
  def body(entry_view_scene_append) do
    """
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
    int elmc_pebble_stream_view_cmds(
        ElmcPebbleApp *app,
        ElmcPebbleDrawCmd *out_cmds,
        int max_cmds,
        int skip,
        int *out_emitted_end) {
      if (!app || !app->initialized) return -1;
      if (skip < 0) return -1;
      if (out_cmds && max_cmds <= 0) return -1;

      ElmcValue *direct_model = elmc_worker_model(&app->worker);
      if (!direct_model) return -2;

      ElmcSceneWriter writer;
      elmc_scene_writer_init_stream(&writer, app, out_cmds, max_cmds, skip);
      ElmcValue *direct_args[] = { direct_model };
      RC rc = #{entry_view_scene_append}(direct_args, 1, &writer);
      elmc_release(direct_model);
      if (rc != RC_SUCCESS) return -1;
      if (out_emitted_end) *out_emitted_end = writer.command_count;
      return out_cmds ? writer.out_count : writer.command_count;
    }
    #endif

    """
  end
end
