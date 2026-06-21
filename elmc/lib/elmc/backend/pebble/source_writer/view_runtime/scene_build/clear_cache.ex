defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.SceneBuild.ClearCache do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_pebble_clear_view_cache(ElmcPebbleApp *app) {
  if (!app) return;
  if (app->stream_view_result) {
    elmc_release(app->stream_view_result);
    app->stream_view_result = NULL;
  }
    }

"""
  end
end
