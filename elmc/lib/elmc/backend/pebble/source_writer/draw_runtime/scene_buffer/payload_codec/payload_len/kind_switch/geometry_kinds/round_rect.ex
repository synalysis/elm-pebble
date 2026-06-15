defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.GeometryKinds.RoundRect do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
      case ELMC_PEBBLE_DRAW_ROUND_RECT:
        if (elmc_scene_bounds_fit_i16(cmd) && elmc_scene_value_fits_i16(cmd->p4)) {
          return elmc_scene_value_fits_u8(cmd->p5) ? ELMC_SCENE_PL_ROUND_U8 : ELMC_SCENE_PL_ROUND_I32;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
"""
  end
end
