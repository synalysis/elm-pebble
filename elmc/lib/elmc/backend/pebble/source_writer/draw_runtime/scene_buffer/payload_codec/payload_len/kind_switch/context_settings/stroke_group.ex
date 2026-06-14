defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.ContextSettings.StrokeGroup do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH || ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
    #if ELMC_PEBBLE_FEATURE_DRAW_STROKE_WIDTH
      case ELMC_PEBBLE_DRAW_STROKE_WIDTH:
    #endif
    #if ELMC_PEBBLE_FEATURE_DRAW_ANTIALIASED
      case ELMC_PEBBLE_DRAW_ANTIALIASED:
    #endif
        return elmc_scene_value_fits_u8(cmd->p0) ? ELMC_SCENE_PL_U8 : ELMC_SCENE_PL_I32;
    #endif
"""
  end
end
