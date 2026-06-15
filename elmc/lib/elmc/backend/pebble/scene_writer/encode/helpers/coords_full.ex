defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.CoordsFull do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        static int elmc_scene_writer_write_coords_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          return elmc_scene_writer_put_i16(writer, cmd->p3);
        }

        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
        static int elmc_scene_writer_write_text_bounds_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p3); if (rc != 0) return rc;
          return elmc_scene_writer_put_i16(writer, cmd->p4);
        }
        #endif

        static int elmc_scene_writer_write_full_i32s(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
          return elmc_scene_writer_put_i32(writer, cmd->p5);
        }

"""
  end
end
