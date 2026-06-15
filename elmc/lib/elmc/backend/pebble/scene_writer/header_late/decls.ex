defmodule Elmc.Backend.Pebble.SceneWriter.HeaderLate.Decls do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_scene_writer_push_cmd(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd);
    void elmc_draw_cmd_init(ElmcPebbleDrawCmd *cmd, int32_t kind);

    """
  end
end
