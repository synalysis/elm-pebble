defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ValueHelpers.FitChecks do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_PIXEL || ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT || ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL || ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
    static int elmc_scene_value_fits_i16(int32_t value) {
      return value >= -32768 && value <= 32767;
    }
    #endif

    static int elmc_scene_value_fits_u8(int32_t value) {
      return value >= 0 && value <= 255;
    }

    #if ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
    static int elmc_scene_bounds_fit_i16(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return 0;
      return elmc_scene_value_fits_i16(cmd->p0) &&
             elmc_scene_value_fits_i16(cmd->p1) &&
             elmc_scene_value_fits_i16(cmd->p2) &&
             elmc_scene_value_fits_i16(cmd->p3);
    }
    #endif

    """
  end
end
