defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.IsVisual do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_cmd_is_visual(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return 0;
      switch (cmd->kind) {
        case ELMC_PEBBLE_DRAW_CLEAR:
        case ELMC_PEBBLE_DRAW_PIXEL:
        case ELMC_PEBBLE_DRAW_LINE:
        case ELMC_PEBBLE_DRAW_RECT:
        case ELMC_PEBBLE_DRAW_FILL_RECT:
        case ELMC_PEBBLE_DRAW_ROUND_RECT:
        case ELMC_PEBBLE_DRAW_ARC:
        case ELMC_PEBBLE_DRAW_FILL_RADIAL:
        case ELMC_PEBBLE_DRAW_CIRCLE:
        case ELMC_PEBBLE_DRAW_FILL_CIRCLE:
        case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
        case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
        case ELMC_PEBBLE_DRAW_TEXT:
        case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT:
        case ELMC_PEBBLE_DRAW_ROTATED_BITMAP:
        case ELMC_PEBBLE_DRAW_VECTOR_AT:
        case ELMC_PEBBLE_DRAW_VECTOR_SEQUENCE_AT:
      #if ELMC_PEBBLE_FEATURE_DRAW_PATH
        case ELMC_PEBBLE_DRAW_PATH_FILLED:
        case ELMC_PEBBLE_DRAW_PATH_OUTLINE:
        case ELMC_PEBBLE_DRAW_PATH_OUTLINE_OPEN:
      #endif
          return 1;
        default:
          return 0;
      }
    }

"""
  end
end
