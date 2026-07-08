defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.StreamViewFetch.ModelInvoke do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body(Types.c_symbol(), boolean()) :: Types.c_source()
  def body(entry_view_fn, direct_abi?) do
    view_call =
      if direct_abi? do
        "RC view_rc = #{entry_view_fn}(&result, model);"
      else
        "RC view_rc = #{entry_view_fn}(&result, args, 1);"
      end

    args_setup =
      if direct_abi? do
        ""
      else
        "ElmcValue *args[] = { model };\n"
      end

    """
              // #region agent log
              elmc_agent_scene_probe(0xED996180);
              // #endregion
              ElmcValue *model = elmc_worker_model(&app->worker);
              // #region agent log
              elmc_agent_scene_probe(model ? 0xED996181 : 0xED99618F);
              // #endregion
              if (!model) return -2;
              #{args_setup}              // #region agent log
              elmc_agent_scene_probe(0xED996190);
              // #endregion
              elmc_pebble_heap_log("view:start");
              #{view_call}
              elmc_pebble_heap_log("view:end");
              if (view_rc != RC_SUCCESS) {
                ELMC_RC_LOG_FAIL(view_rc, "elmc_pebble_view_commands_raw_impl", "view");
                elmc_release(model);
                return -2;
              }
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
