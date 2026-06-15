defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.PutBytes.PutU8 do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_scene_put_u8(ElmcPebbleApp *app, unsigned char value) {
      int rc = elmc_pebble_scene_reserve(app, 1);
      if (rc != 0) return rc;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      ElmcPebbleSceneChunk *tail = elmc_pebble_scene_chunk_tail(app->scene.chunks);
      if (!tail || tail->used >= ELMC_PEBBLE_SCENE_CHUNK_SIZE) {
        if (elmc_pebble_scene_chunk_append(&app->scene) != 0) return -2;
        tail = elmc_pebble_scene_chunk_tail(app->scene.chunks);
        if (!tail) return -2;
      }
      tail->bytes[tail->used++] = value;
      app->scene.byte_count++;
    #else
      app->scene.bytes[app->scene.byte_count++] = value;
    #endif
      elmc_pebble_scene_hash_byte(app, value);
      return 0;
    }

    """
  end
end
