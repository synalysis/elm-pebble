defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.TextKinds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      case ELMC_PEBBLE_DRAW_TEXT:
        if (elmc_scene_value_fits_i16(cmd->p1) &&
            elmc_scene_value_fits_i16(cmd->p2) &&
            elmc_scene_value_fits_i16(cmd->p3) &&
            elmc_scene_value_fits_i16(cmd->p4)) {
          return ELMC_SCENE_PL_TEXT_BASE + 1 + text_len;
        }
        return ELMC_SCENE_PL_FULL + 1 + text_len;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
      case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
        if (elmc_scene_value_fits_i16(cmd->p1) && elmc_scene_value_fits_i16(cmd->p2)) {
          return ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + text_len;
        }
        return ELMC_SCENE_PL_FULL + 1 + text_len;
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
      case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
        if (elmc_scene_value_fits_i16(cmd->p1) && elmc_scene_value_fits_i16(cmd->p2)) {
          return ELMC_SCENE_PL_COORDS_COLOR_I32;
        }
        return ELMC_SCENE_PL_FULL;
    #endif
"""
  end
end
