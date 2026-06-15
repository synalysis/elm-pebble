defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.GeometryKinds.Pixel do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      case ELMC_PEBBLE_DRAW_PIXEL:
        if (elmc_scene_value_fits_i16(cmd->p0) &&
            elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_u8(cmd->p2)) {
          return ELMC_SCENE_PL_PIXEL;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
"""
  end
end
