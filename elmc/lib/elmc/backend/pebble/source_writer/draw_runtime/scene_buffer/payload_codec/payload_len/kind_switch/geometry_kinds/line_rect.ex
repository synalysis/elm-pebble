defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.GeometryKinds.LineRect do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT
    #if ELMC_PEBBLE_FEATURE_DRAW_LINE
      case ELMC_PEBBLE_DRAW_LINE:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_RECT
      case ELMC_PEBBLE_DRAW_RECT:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT
      case ELMC_PEBBLE_DRAW_FILL_RECT:
    #endif
        if (!elmc_scene_bounds_fit_i16(cmd) || cmd->p5 != 0) return ELMC_SCENE_PL_FULL;
        return elmc_scene_value_fits_u8(cmd->p4) ? ELMC_SCENE_PL_COORDS_COLOR_U8 : ELMC_SCENE_PL_COORDS_COLOR_I32;
    #endif
"""
  end
end
