defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.ModelOnlyFetch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
            if (!dedupe && app->stream_view_result) {
              result = app->stream_view_result;
            } else {
              result = elmc_worker_model(&app->worker);
              if (!result) return -2;
              if (!dedupe) {
                app->stream_view_result = result;
              }
            }
    """
  end
end
