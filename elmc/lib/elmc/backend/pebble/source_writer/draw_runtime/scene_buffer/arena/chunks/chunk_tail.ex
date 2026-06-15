defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Chunks.ChunkTail do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static ElmcPebbleSceneChunk *elmc_pebble_scene_chunk_tail(ElmcPebbleSceneChunk *head) {
      ElmcPebbleSceneChunk *tail = head;
      while (tail && tail->next) tail = tail->next;
      return tail;
    }

    """
  end
end
