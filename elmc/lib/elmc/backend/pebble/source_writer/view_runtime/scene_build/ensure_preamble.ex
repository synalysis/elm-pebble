defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.EnsurePreamble do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_ensure_scene(ElmcPebbleApp *app) {
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_ENTER);
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_ensure_scene");
      if (!app || !app->initialized) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -1);
      }
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", -2);
    #endif
      if (!app->scene.dirty) {
        ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure skip clean cmds=%d bytes=%d",
                app->scene.command_count, app->scene.byte_count);
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_ENSURE_SCENE_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_ensure_scene", 0);
      }
      ELMC_PEBBLE_SCENE_LOG("elmc-scene ensure rebuild begin");
      elmc_pebble_prepare_scene_rebuild(app);
      elmc_pebble_scene_reset(app);
"""
  end
end
