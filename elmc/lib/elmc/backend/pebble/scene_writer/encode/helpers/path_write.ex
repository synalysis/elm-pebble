defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.PathWrite do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        static int elmc_scene_writer_write_path_tail(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
        #if ELMC_PEBBLE_FEATURE_DRAW_PATH
          int count = cmd->path_point_count;
          if (count < 0) count = 0;
          if (count > 16) count = 16;
          int rc = elmc_scene_writer_put_u8(writer, (unsigned char)count); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->path_offset_x); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->path_offset_y); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->path_rotation); if (rc != 0) return rc;
          for (int i = 0; i < count; i++) {
            rc = elmc_scene_writer_put_i16(writer, cmd->path_x[i]); if (rc != 0) return rc;
            rc = elmc_scene_writer_put_i16(writer, cmd->path_y[i]); if (rc != 0) return rc;
          }
          return 0;
        #else
          (void)writer;
          (void)cmd;
          return 0;
        #endif
        }
"""
  end
end
