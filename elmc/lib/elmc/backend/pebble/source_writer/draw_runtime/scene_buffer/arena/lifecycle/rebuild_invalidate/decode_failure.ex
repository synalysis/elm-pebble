defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Lifecycle.RebuildInvalidate.DecodeFailure do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_pebble_scene_report_decode_failure(ElmcPebbleApp *app, int rc, int offset) {
      if (!app) return;
      ELMC_PEBBLE_SCENE_LOG("elmc-scene draw decode failed rc=%d offset=%d cmds=%d bytes=%d",
              rc, offset, app->scene.command_count, app->scene.byte_count);
      (void)rc;
      (void)offset;
      elmc_pebble_scene_abort_build(app);
    }

    """
  end
end
