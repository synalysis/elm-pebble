defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.ReadHelpers.PathRead.IsPathKind do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_scene_is_path_kind(int32_t kind) {
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
      return kind == ELMC_PEBBLE_DRAW_PATH_FILLED ||
             kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE ||
             kind == ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN;
    #else
      (void)kind;
      return 0;
    #endif
    }

    """
  end
end
