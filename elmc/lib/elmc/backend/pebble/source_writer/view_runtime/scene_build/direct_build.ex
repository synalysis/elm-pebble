defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.DirectBuild do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.scene_build_bindings()) :: Types.c_source()
  def body(%{entry_view_scene_append: entry_view_scene_append}) do
    """
    #if defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
      {
        ElmcSceneWriter writer;
        elmc_scene_writer_init_app(&writer, app);
        ElmcValue *direct_model = elmc_worker_model(&app->worker);
        if (!direct_model) {
          elmc_pebble_scene_abort_build(app);
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
        }
        ElmcValue *direct_args[] = { direct_model };
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_VIEW_APPEND_ENTER);
        RC rc = #{entry_view_scene_append}(direct_args, 1, &writer);
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_VIEW_APPEND_EXIT);
        elmc_release(direct_model);
        ELMC_PEBBLE_SCENE_LOG("elmc-scene view append rc=%u writer_cmds=%d",
                (unsigned)rc, writer.command_count);
        if (rc != RC_SUCCESS) {
          ELMC_RC_LOG_FAIL(rc, "elmc_pebble_ensure_scene", "view_scene_append");
          elmc_pebble_scene_abort_build(app);
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -1);
        }
      }
    """
  end
end
