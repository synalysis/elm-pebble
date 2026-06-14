defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.GeometryKinds.Circle do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
    #if ELMC_PEBBLE_FEATURE_DRAW_CIRCLE
      case ELMC_PEBBLE_DRAW_CIRCLE:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE
      case ELMC_PEBBLE_DRAW_FILL_CIRCLE:
    #endif
        if (elmc_scene_value_fits_i16(cmd->p0) &&
            elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_i16(cmd->p2) &&
            cmd->p4 == 0 && cmd->p5 == 0) {
          return elmc_scene_value_fits_u8(cmd->p3) ? ELMC_SCENE_PL_CIRCLE_U8 : ELMC_SCENE_PL_CIRCLE_I32;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
"""
  end
end
