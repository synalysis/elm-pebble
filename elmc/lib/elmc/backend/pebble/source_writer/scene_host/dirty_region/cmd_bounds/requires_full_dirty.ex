defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.RequiresFullDirty do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_cmd_requires_full_dirty(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return 1;
      switch (cmd->kind) {
        case ELMC_PEBBLE_DRAW_CLEAR:
        case ELMC_PEBBLE_DRAW_PUSH_CONTEXT:
        case ELMC_PEBBLE_DRAW_POP_CONTEXT:
        case ELMC_PEBBLE_DRAW_STROKE_WIDTH:
        case ELMC_PEBBLE_DRAW_ANTIALIASED:
        case ELMC_PEBBLE_DRAW_STROKE_COLOR:
        case ELMC_PEBBLE_DRAW_FILL_COLOR:
        case ELMC_PEBBLE_DRAW_TEXT_COLOR:
        case ELMC_PEBBLE_DRAW_CONTEXT_GROUP:
        case ELMC_PEBBLE_DRAW_COMPOSITING_MODE:
        case ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT:
        case ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT:
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
