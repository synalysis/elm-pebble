defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.ContextSettings.ColorClearGroup do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR || ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR || ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR || ELMC_PEBBLE_FEATURE_DRAW_CLEAR || ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_COLOR
      case ELMC_PEBBLE_DRAW_STROKE_COLOR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_FILL_COLOR
      case ELMC_PEBBLE_DRAW_FILL_COLOR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT_COLOR
      case ELMC_PEBBLE_DRAW_TEXT_COLOR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_CLEAR
      case ELMC_PEBBLE_DRAW_CLEAR:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_COMPOSITING_MODE
      case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
    #endif
        return elmc_scene_value_fits_u8(cmd->p0) ? ELMC_SCENE_PL_U8 : ELMC_SCENE_PL_I32;
    #endif
"""
  end
end
