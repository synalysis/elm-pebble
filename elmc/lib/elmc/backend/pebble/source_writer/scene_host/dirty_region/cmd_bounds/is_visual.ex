defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.IsVisual do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables.DrawKindLuts
  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    lut = DrawKindLuts.predicate_lut_c("elmc_pebble_draw_kind_visual_lut", DrawKindLuts.visual_kinds())

    """
    #{lut}
    static int elmc_pebble_cmd_is_visual(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return 0;
      return #{DrawKindLuts.predicate_lookup_c("elmc_pebble_draw_kind_visual_lut", "cmd->kind")};
    }

    """
  end
end
