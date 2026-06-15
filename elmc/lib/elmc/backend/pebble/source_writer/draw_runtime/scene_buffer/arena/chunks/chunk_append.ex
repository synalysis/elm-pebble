defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Chunks.ChunkAppend do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_scene_chunk_append(ElmcPebbleSceneBuffer *scene) {
      ElmcPebbleSceneChunk *chunk = (ElmcPebbleSceneChunk *)malloc(sizeof(ElmcPebbleSceneChunk));
      if (!chunk) return -2;
      chunk->next = NULL;
      chunk->used = 0;
      if (!scene->chunks) {
        scene->chunks = chunk;
      } else {
        ElmcPebbleSceneChunk *tail = elmc_pebble_scene_chunk_tail(scene->chunks);
        if (!tail) {
          free(chunk);
          return -2;
        }
        tail->next = chunk;
      }
      scene->byte_capacity += ELMC_PEBBLE_SCENE_CHUNK_SIZE;
      return 0;
    }

    """
  end
end
