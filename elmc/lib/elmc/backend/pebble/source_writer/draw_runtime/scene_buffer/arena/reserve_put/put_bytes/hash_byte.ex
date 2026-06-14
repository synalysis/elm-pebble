defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.PutBytes.HashByte do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static void elmc_pebble_scene_hash_byte(ElmcPebbleApp *app, unsigned char byte) {
      app->scene.hash ^= (uint64_t)byte;
      app->scene.hash *= 1099511628211ULL;
    }

    """
  end
end
