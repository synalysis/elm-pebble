defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Chunks.ChunksFree do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_chunks_free(ElmcPebbleSceneBuffer *scene) {
      if (!scene) return;
      while (scene->chunks) {
        ElmcPebbleSceneChunk *next = scene->chunks->next;
        free(scene->chunks);
        scene->chunks = next;
      }
    }

    """
  end
end
