defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.VisualBounds.PixelLine do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_pebble_cmd_visual_bounds(const ElmcPebbleDrawCmd *cmd, ElmcPebbleRect *out) {
      if (!cmd || !out) return 0;
      switch (cmd->kind) {
        case ELMC_PEBBLE_DRAW_PIXEL:
          elmc_rect_set(out, cmd->p0, cmd->p1, 1, 1);
          return 1;
        case ELMC_PEBBLE_DRAW_LINE: {
          int x1 = elmc_min_int(cmd->p0, cmd->p2);
          int y1 = elmc_min_int(cmd->p1, cmd->p3);
          int x2 = elmc_max_int(cmd->p0, cmd->p2);
          int y2 = elmc_max_int(cmd->p1, cmd->p3);
          elmc_rect_set(out, x1, y1, x2 - x1 + 1, y2 - y1 + 1);
          return 1;
        }
    """
  end
end
