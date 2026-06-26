defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.DirtyRegion.CmdBounds.RequiresFullDirty do
  @moduledoc false

  alias Elmc.Backend.Pebble.Kinds.Tables.DrawKindLuts
  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    lut =
      DrawKindLuts.predicate_lut_c(
        "elmc_pebble_draw_kind_full_dirty_lut",
        DrawKindLuts.full_dirty_kinds()
      )

    """
    #{lut}
    static int elmc_pebble_cmd_requires_full_dirty(const ElmcPebbleDrawCmd *cmd) {
      if (!cmd) return 1;
      return #{DrawKindLuts.predicate_lookup_c("elmc_pebble_draw_kind_full_dirty_lut", "cmd->kind")};
    }

    """
  end
end
