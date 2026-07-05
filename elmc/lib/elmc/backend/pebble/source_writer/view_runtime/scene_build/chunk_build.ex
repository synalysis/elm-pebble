defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.ChunkBuild do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #else
      enum { BUILD_CHUNK_GUARD = 1024 };
      ElmcPebbleDrawCmd cmd;
      ElmcSceneWriter writer;
      int skip = 0;
      elmc_scene_writer_init_app(&writer, app);
      for (int chunk = 0; chunk < BUILD_CHUNK_GUARD; chunk++) {
        int emitted_end = 0;
        int count = elmc_pebble_view_commands_raw_impl(app, &cmd, 1, skip, 0, &emitted_end);
        if (count < 0) {
          elmc_pebble_scene_abort_build(app);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", count);
        }
        if (count == 0) break;
        RC rc = elmc_scene_writer_push_cmd(&writer, &cmd);
        if (rc != RC_SUCCESS) {
          elmc_pebble_scene_abort_build(app);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
        }
        skip = emitted_end;
      }
    #endif
"""
  end
end
