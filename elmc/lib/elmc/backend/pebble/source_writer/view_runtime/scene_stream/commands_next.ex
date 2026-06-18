defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneStream.CommandsNext do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_scene_commands_next(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds) {
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_ENTER);
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_scene_commands_next");
      if (!app || !out_cmds || max_cmds <= 0) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", -1);
      }
    #if !ELMC_PEBBLE_SCENE_CACHE_ENABLED
      int direct_count = elmc_pebble_view_commands_raw_impl(app, out_cmds, max_cmds, 0, 0, NULL);
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", direct_count);
    #endif
      /* Scene cache is built off the draw stack (deferred timer in the app template).
         While dirty or empty, skip drawing rather than calling ensure_scene here.
         Mid-stream reads may finish draining a cached scene after dirty is set. */
      if (app->scene.byte_count <= 0) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", 0);
      }
      if (app->scene.dirty && app->scene_draw_byte_offset <= 0) {
        ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
        ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", 0);
      }
      int rc = 0;
      int byte_offset = app->scene_draw_byte_offset;
      int count = 0;
      while (byte_offset < app->scene.byte_count && count < max_cmds) {
        ElmcPebbleDrawCmd cmd;
        rc = elmc_pebble_scene_decode_record(app->scene.bytes, app->scene.byte_count, &byte_offset, &cmd);
        if (rc != 0) {
          ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", rc);
        }
        out_cmds[count++] = cmd;
      }
      app->scene_draw_byte_offset = byte_offset;
      ELMC_DRAW_PATH_PROBE(ELMC_DRAW_PATH_SCENE_NEXT_EXIT);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_scene_commands_next", count);
    }

"""
  end
end
