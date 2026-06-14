defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.PutBytes.PutI32 do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_scene_put_i32(ElmcPebbleApp *app, int32_t value) {
      uint32_t raw = (uint32_t)value;
      int rc = elmc_pebble_scene_reserve(app, 4);
      if (rc != 0) return rc;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      for (int i = 0; i < 4; i++) {
        unsigned char byte = (unsigned char)((raw >> (i * 8)) & 0xff);
        rc = elmc_pebble_scene_put_u8(app, byte);
        if (rc != 0) return rc;
      }
      return 0;
    #else
      for (int i = 0; i < 4; i++) {
        unsigned char byte = (unsigned char)((raw >> (i * 8)) & 0xff);
        app->scene.bytes[app->scene.byte_count++] = byte;
        elmc_pebble_scene_hash_byte(app, byte);
      }
      return 0;
    #endif
    }

    """
  end
end
