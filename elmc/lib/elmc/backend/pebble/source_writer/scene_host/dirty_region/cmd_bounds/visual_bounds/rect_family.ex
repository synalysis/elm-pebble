defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.VisualBounds.RectFamily do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        case ELMC_PEBBLE_DRAW_RECT:
        case ELMC_PEBBLE_DRAW_FILL_RECT:
        case ELMC_PEBBLE_DRAW_ROUND_RECT:
        case ELMC_PEBBLE_DRAW_ARC:
        case ELMC_PEBBLE_DRAW_FILL_RADIAL:
          elmc_rect_set(out, cmd->p0, cmd->p1, cmd->p2, cmd->p3);
          return !elmc_rect_empty(out);
        case ELMC_PEBBLE_DRAW_TEXT:
        case ELMC_PEBBLE_DRAW_BITMAP_IN_RECT:
          elmc_rect_set(out, cmd->p1, cmd->p2, cmd->p3, cmd->p4);
          return !elmc_rect_empty(out);
    """
  end
end
