defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.Preamble do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_view_commands_raw_impl(ElmcPebbleApp *app, ElmcPebbleDrawCmd *out_cmds, int max_cmds, int skip, int dedupe, int *out_emitted_end) {
      if (!app || !app->initialized || !out_cmds || max_cmds <= 0) return -1;
      if (skip < 0) return -1;
      if (out_emitted_end) *out_emitted_end = skip;
    #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
      int count = 0;
      ElmcValue *result = NULL;
      int result_is_cached = dedupe ? 0 : 1;
      if (!dedupe && skip == 0) {
        elmc_pebble_clear_view_cache(app);
      }
    #endif
    """
  end
end
