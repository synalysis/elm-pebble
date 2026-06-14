defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.StreamViewFetch.CachedResult do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
            if (!dedupe && app->stream_view_result) {
              // #region agent log
              elmc_agent_scene_probe(0xED9961A0);
              // #endregion
              result = app->stream_view_result;
            } else {
"""
  end
end
