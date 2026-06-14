defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.StreamViewFetch.ModelInvoke do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.c_symbol()) :: Types.c_source()
  def body(entry_view_fn) do
    """
              // #region agent log
              elmc_agent_scene_probe(0xED996180);
              // #endregion
              ElmcValue *model = elmc_worker_model(&app->worker);
              // #region agent log
              elmc_agent_scene_probe(model ? 0xED996181 : 0xED99618F);
              // #endregion
              if (!model) return -2;
              ElmcValue *args[] = { model };
              // #region agent log
              elmc_agent_scene_probe(0xED996190);
              // #endregion
              elmc_pebble_heap_log("view:start");
              result = #{entry_view_fn}(args, 1);
              elmc_pebble_heap_log("view:end");
              if (!result) {
                ELMC_RC_LOG_FAIL(RC_ERR_OUT_OF_MEMORY, "elmc_pebble_view_commands_raw_impl", "view");
                elmc_release(model);
                return -2;
              }
              // #region agent log
              elmc_agent_scene_probe(0xED996191);
              // #endregion
              elmc_release(model);
"""
  end
end
