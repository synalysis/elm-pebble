defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ReservePut.ReserveGrow.Reserve do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_scene_reserve(ElmcPebbleApp *app, int extra) {
      if (!app || extra < 0) return -1;
      int needed = app->scene.byte_count + extra;
      if (needed <= app->scene.byte_capacity) return 0;
      return elmc_pebble_scene_reserve_capacity(app, needed);
    }

    """
  end
end
