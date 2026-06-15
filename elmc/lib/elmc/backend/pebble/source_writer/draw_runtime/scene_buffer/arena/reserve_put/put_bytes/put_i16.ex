defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.PutBytes.PutI16 do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_scene_put_i16(ElmcPebbleApp *app, int32_t value) {
      if (value < -32768) value = -32768;
      if (value > 32767) value = 32767;
      uint16_t raw = (uint16_t)((int16_t)value);
      int rc = elmc_pebble_scene_reserve(app, 2);
      if (rc != 0) return rc;
      unsigned char b0 = (unsigned char)(raw & 0xff);
      unsigned char b1 = (unsigned char)((raw >> 8) & 0xff);
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      rc = elmc_pebble_scene_put_u8(app, b0);
      if (rc != 0) return rc;
      return elmc_pebble_scene_put_u8(app, b1);
    #else
      app->scene.bytes[app->scene.byte_count++] = b0;
      app->scene.bytes[app->scene.byte_count++] = b1;
      elmc_pebble_scene_hash_byte(app, b0);
      elmc_pebble_scene_hash_byte(app, b1);
      return 0;
    #endif
    }

    """
  end
end
