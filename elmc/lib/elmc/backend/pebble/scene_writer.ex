defmodule Elmc.Backend.Pebble.SceneWriter do
  @moduledoc false

  @spec header_early_declarations() :: String.t()
  def header_early_declarations do
    """
    typedef struct ElmcPebbleApp ElmcPebbleApp;

    enum {
      ELMC_SCENE_PL_EMPTY = 0,
      ELMC_SCENE_PL_U8 = 1,
      ELMC_SCENE_PL_I32 = 4,
      ELMC_SCENE_PL_PIXEL = 5,
      ELMC_SCENE_PL_CIRCLE_U8 = 7,
      ELMC_SCENE_PL_TEXT_LABEL_BASE = 8,
      ELMC_SCENE_PL_COORDS_COLOR_U8 = 9,
      ELMC_SCENE_PL_CIRCLE_I32 = 10,
      ELMC_SCENE_PL_ROUND_U8 = 11,
      ELMC_SCENE_PL_COORDS_COLOR_I32 = 12,
      ELMC_SCENE_PL_ROUND_I32 = 14,
      ELMC_SCENE_PL_TEXT_BASE = 16,
      ELMC_SCENE_PL_FULL = 24
    };

    typedef struct {
      ElmcPebbleApp *app;
      int command_count;
    } ElmcSceneWriter;

    void elmc_scene_writer_init_app(ElmcSceneWriter *writer, ElmcPebbleApp *app);
    """
  end

  @spec header_late_declarations() :: String.t()
  def header_late_declarations do
    """
    int elmc_scene_writer_push_cmd(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd);
    void elmc_draw_cmd_init(ElmcPebbleDrawCmd *cmd, int32_t kind);
    int elmc_pebble_scene_decode_record(
        const unsigned char *bytes,
        int byte_count,
        int *offset,
        ElmcPebbleDrawCmd *out_cmd);
    """
  end

  @spec source_implementation() :: String.t()
  def source_implementation do
    """
    void elmc_scene_writer_init_app(ElmcSceneWriter *writer, ElmcPebbleApp *app) {
      if (!writer) return;
      writer->app = app;
      writer->command_count = 0;
    }

    static int elmc_scene_writer_put_u8(ElmcSceneWriter *writer, unsigned char value) {
      if (!writer || !writer->app) return -1;
      return elmc_pebble_scene_put_u8(writer->app, value);
    }

    static int elmc_scene_writer_put_i16(ElmcSceneWriter *writer, int32_t value) {
      if (!writer || !writer->app) return -1;
      return elmc_scene_put_i16(writer->app, value);
    }

    static int elmc_scene_writer_put_i32(ElmcSceneWriter *writer, int32_t value) {
      if (!writer || !writer->app) return -1;
      return elmc_pebble_scene_put_i32(writer->app, value);
    }

    static int elmc_scene_writer_write_text_tail(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
      if (!writer || !writer->app) return -1;
      int text_len = elmc_scene_text_len(cmd);
      int rc = elmc_scene_writer_put_u8(writer, (unsigned char)text_len);
      if (rc != 0) return rc;
      rc = elmc_pebble_scene_reserve(writer->app, text_len);
      if (rc != 0) return rc;
      for (int i = 0; i < text_len; i++) {
        unsigned char byte = (unsigned char)cmd->text[i];
        writer->app->scene.bytes[writer->app->scene.byte_count++] = byte;
        elmc_pebble_scene_hash_byte(writer->app, byte);
      }
      return 0;
    }

    static int elmc_scene_writer_write_coords_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
      int rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
      return elmc_scene_writer_put_i16(writer, cmd->p3);
    }

    static int elmc_scene_writer_write_text_bounds_i16(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
      int rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i16(writer, cmd->p3); if (rc != 0) return rc;
      return elmc_scene_writer_put_i16(writer, cmd->p4);
    }

    static int elmc_scene_writer_write_full_i32s(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
      int rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
      rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
      return elmc_scene_writer_put_i32(writer, cmd->p5);
    }

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

    static int elmc_scene_writer_encode_payload(
        ElmcSceneWriter *writer,
        const ElmcPebbleDrawCmd *cmd,
        int payload_len) {
      int rc = 0;
      if (payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE &&
          cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len == ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + elmc_scene_text_len(cmd)) {
        int rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc2 != 0) return rc2;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
      switch (payload_len) {
      case ELMC_SCENE_PL_EMPTY:
        return 0;
      case ELMC_SCENE_PL_U8:
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p0);
      case ELMC_SCENE_PL_I32:
        return elmc_scene_writer_put_i32(writer, cmd->p0);
      case ELMC_SCENE_PL_PIXEL:
        rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p2);
      case ELMC_SCENE_PL_COORDS_COLOR_U8:
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p4);
      case ELMC_SCENE_PL_COORDS_COLOR_I32:
        if (cmd->kind == ELMC_PEBBLE_DRAW_TEXT_INT_WITH_FONT) {
          rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
          rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
          return elmc_scene_writer_put_i32(writer, cmd->p3);
        }
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        return elmc_scene_writer_put_i32(writer, cmd->p4);
      case ELMC_SCENE_PL_CIRCLE_U8:
        rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p3);
      case ELMC_SCENE_PL_CIRCLE_I32:
        rc = elmc_scene_writer_put_i16(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc != 0) return rc;
        return elmc_scene_writer_put_i32(writer, cmd->p3);
      case ELMC_SCENE_PL_ROUND_U8:
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p4); if (rc != 0) return rc;
        return elmc_scene_writer_put_u8(writer, (unsigned char)cmd->p5);
      case ELMC_SCENE_PL_ROUND_I32:
        rc = elmc_scene_writer_write_coords_i16(writer, cmd); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i16(writer, cmd->p4); if (rc != 0) return rc;
        return elmc_scene_writer_put_i32(writer, cmd->p5);
      default:
        break;
      }
      if (payload_len >= ELMC_SCENE_PL_TEXT_BASE &&
          cmd->kind == ELMC_PEBBLE_DRAW_TEXT &&
          payload_len == ELMC_SCENE_PL_TEXT_BASE + 1 + elmc_scene_text_len(cmd)) {
        int rc2 = elmc_scene_writer_write_text_bounds_i16(writer, cmd); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i32(writer, cmd->p5); if (rc2 != 0) return rc2;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
      if (payload_len >= ELMC_SCENE_PL_TEXT_LABEL_BASE &&
          cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT &&
          payload_len == ELMC_SCENE_PL_TEXT_LABEL_BASE + 1 + elmc_scene_text_len(cmd)) {
        int rc2 = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p1); if (rc2 != 0) return rc2;
        rc2 = elmc_scene_writer_put_i16(writer, cmd->p2); if (rc2 != 0) return rc2;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
      if (payload_len >= ELMC_SCENE_PL_FULL &&
          (!elmc_scene_is_path_kind(cmd->kind) ||
           payload_len == ELMC_SCENE_PL_FULL + elmc_scene_path_extra_size(cmd))) {
        rc = elmc_scene_writer_write_full_i32s(writer, cmd); if (rc != 0) return rc;
        if (elmc_scene_is_path_kind(cmd->kind) && payload_len > ELMC_SCENE_PL_FULL) {
          rc = elmc_scene_writer_write_path_tail(writer, cmd); if (rc != 0) return rc;
        }
        return 0;
      }
      if (payload_len > ELMC_SCENE_PL_FULL &&
          (cmd->kind == ELMC_PEBBLE_DRAW_TEXT ||
           cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT)) {
        rc = elmc_scene_writer_put_i32(writer, cmd->p0); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p1); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p2); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p3); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p4); if (rc != 0) return rc;
        rc = elmc_scene_writer_put_i32(writer, cmd->p5); if (rc != 0) return rc;
        return elmc_scene_writer_write_text_tail(writer, cmd);
      }
      return -4;
    }

    int elmc_scene_writer_push_cmd(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
      if (!writer || !writer->app || !cmd) return -1;
      int payload_len = elmc_pebble_scene_payload_len(cmd);
      if (payload_len < 0 || payload_len > 255) return -3;
      int rc = elmc_scene_writer_put_u8(writer, (unsigned char)cmd->kind);
      if (rc != 0) return rc;
      rc = elmc_scene_writer_put_u8(writer, (unsigned char)payload_len);
      if (rc != 0) return rc;
      rc = elmc_scene_writer_encode_payload(writer, cmd, payload_len);
      if (rc != 0) return rc;
      writer->command_count += 1;
      writer->app->scene.command_count = writer->command_count;
      return 0;
    }
    """
  end
end
