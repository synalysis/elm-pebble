defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.CoordsFull do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT
        static int elmc_scene_writer_write_coords_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          return elmc_scene_writer_put_i16(writer, cmd->p3);
        }
        #endif

        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT
        static int elmc_scene_writer_write_text_bounds_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p3); if (rc != 0) return rc;
          return elmc_scene_writer_put_i16(writer, cmd->p4);
        }
        #endif

        #if ELMC_PEBBLE_FEATURE_DRAW_PATH || ELMC_PEBBLE_FEATURE_DRAW_LINE || ELMC_PEBBLE_FEATURE_DRAW_RECT || ELMC_PEBBLE_FEATURE_DRAW_FILL_RECT || ELMC_PEBBLE_FEATURE_DRAW_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_FILL_CIRCLE || ELMC_PEBBLE_FEATURE_DRAW_ROUND_RECT || ELMC_PEBBLE_FEATURE_DRAW_ARC || ELMC_PEBBLE_FEATURE_DRAW_FILL_RADIAL || ELMC_PEBBLE_FEATURE_DRAW_BITMAP_IN_RECT || ELMC_PEBBLE_FEATURE_DRAW_VECTOR_AT || ELMC_PEBBLE_FEATURE_DRAW_VECTOR_SEQUENCE_AT || ELMC_PEBBLE_FEATURE_DRAW_BITMAP_SEQUENCE_AT || ELMC_PEBBLE_FEATURE_DRAW_ROTATED_BITMAP || ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL || ELMC_PEBBLE_FEATURE_DRAW_TEXT_INT
        static int elmc_scene_writer_write_full_i32s(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          int rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
          return elmc_scene_writer_put_i32(writer, cmd->p5);
        }
        #endif

"""
  end
end
