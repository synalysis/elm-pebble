defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.ResultFetch.StreamViewFetch.ResultShape do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
              // #region agent log
              elmc_agent_scene_probe(0xED996200);
              if (!result) {
                elmc_agent_scene_probe(0xED996213);
              } else if (result->tag == ELMC_TAG_TUPLE2) {
                elmc_agent_scene_probe(0xED996211);
              } else if (result->tag == ELMC_TAG_LIST) {
                elmc_agent_scene_probe(0xED996212);
              } else {
                elmc_agent_scene_probe(0xED996210);
              }
              // #endregion
              if (!dedupe) {
                if (app->stream_view_result) {
                  elmc_release(app->stream_view_result);
                }
                app->stream_view_result = result;
              }
            }
      #endif
"""
  end
end
