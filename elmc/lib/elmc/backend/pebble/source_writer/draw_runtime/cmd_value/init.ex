defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Init do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    void elmc_draw_cmd_init(ElmcPebbleDrawCmd *cmd, int32_t kind) {
          if (!cmd) return;
          cmd->kind = kind;
          cmd->p0 = 0;
          cmd->p1 = 0;
          cmd->p2 = 0;
          cmd->p3 = 0;
          cmd->p4 = 0;
          cmd->p5 = 0;
        #if ELMC_PEBBLE_FEATURE_DRAW_PATH
          cmd->path_point_count = 0;
          cmd->path_offset_x = 0;
          cmd->path_offset_y = 0;
          cmd->path_rotation = 0;
          for (int i = 0; i < 16; i++) {
            cmd->path_x[i] = 0;
            cmd->path_y[i] = 0;
          }
        #endif
          cmd->text[0] = '\0';
        }

"""
  end
end
