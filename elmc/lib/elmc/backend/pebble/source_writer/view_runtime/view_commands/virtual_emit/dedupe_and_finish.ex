defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.VirtualEmit.DedupeAndFinish do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        // #region agent log
        elmc_agent_scene_probe(count == 0 ? 0xED996500 : 0xED996501);
        elmc_agent_scene_probe(0xED997100 | (uint32_t)(count > 255 ? 255 : count));
        // #endregion

        if (skip == 0 && dedupe && extracted == 0 && count < max_cmds) {
          uint64_t next_hash = elmc_hash_value(ops, 0);
          if (app->has_prev_ui &&
              app->prev_window_id == window_id &&
              app->prev_layer_id == layer_id &&
              app->prev_ops_hash == next_hash) {
            count = 0;
          }
          app->has_prev_ui = 1;
          app->prev_window_id = window_id;
          app->prev_layer_id = layer_id;
          app->prev_ops_hash = next_hash;
        }

        if (!result_is_cached) {
          elmc_release(result);
        }
        return count;
    """
  end
end
