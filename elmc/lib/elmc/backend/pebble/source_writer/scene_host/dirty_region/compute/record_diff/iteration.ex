defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.Compute.RecordDiff.Iteration do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        const unsigned char *old_record = NULL;
        const unsigned char *new_record = NULL;
        int old_len = 0;
        int new_len = 0;
        ElmcPebbleDrawCmd old_cmd;
        ElmcPebbleDrawCmd new_cmd;
        int old_rc = elmc_pebble_scene_next_record(app->prev_scene.bytes, app->prev_scene.byte_count,
                                                   &old_offset, &old_record, &old_len, &old_cmd);
        int new_rc = elmc_pebble_scene_next_record(app->scene.bytes, app->scene.byte_count,
                                                   &new_offset, &new_record, &new_len, &new_cmd);
        if (old_rc < 0 || new_rc < 0) {
          return;
        }
        if (old_rc == 1 && new_rc == 1) {
          break;
        }
        if (old_rc == 0 && new_rc == 0 && old_len == new_len && memcmp(old_record, new_record, (size_t)old_len) == 0) {
          continue;
        }

        if ((old_rc == 0 && elmc_pebble_cmd_requires_full_dirty(&old_cmd)) ||
            (new_rc == 0 && elmc_pebble_cmd_requires_full_dirty(&new_cmd))) {
          return;
        }

        if (old_rc == 0 && elmc_pebble_cmd_is_visual(&old_cmd)) {
          ElmcPebbleRect bounds;
          if (!elmc_pebble_cmd_visual_bounds(&old_cmd, &bounds)) return;
          elmc_rect_union_into(&union_rect, &bounds);
        }
        if (new_rc == 0 && elmc_pebble_cmd_is_visual(&new_cmd)) {
          ElmcPebbleRect bounds;
          if (!elmc_pebble_cmd_visual_bounds(&new_cmd, &bounds)) return;
          elmc_rect_union_into(&union_rect, &bounds);
        }
      }
"""
  end
end
