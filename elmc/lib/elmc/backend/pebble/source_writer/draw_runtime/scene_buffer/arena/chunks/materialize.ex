defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Chunks.Materialize do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_scene_materialize_chunks(ElmcPebbleSceneBuffer *scene) {
      if (!scene || !scene->chunks || scene->byte_count <= 0) return 0;
      unsigned char *dest = scene->bytes;
      if (!dest || scene->byte_capacity < scene->byte_count) {
        dest = (unsigned char *)realloc(scene->bytes, (size_t)scene->byte_count);
        if (!dest) return -2;
        scene->bytes = dest;
        scene->byte_capacity = scene->byte_count;
      }
      int pos = 0;
      for (ElmcPebbleSceneChunk *chunk = scene->chunks; chunk; chunk = chunk->next) {
        memcpy(dest + pos, chunk->bytes, (size_t)chunk->used);
        pos += chunk->used;
      }
      elmc_pebble_scene_chunks_free(scene);
      return 0;
    }
    """
  end
end
