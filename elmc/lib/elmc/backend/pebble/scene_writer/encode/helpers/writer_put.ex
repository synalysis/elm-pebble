defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.WriterPut do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec stream_body() :: Types.c_source()
  def stream_body do
    """
        void elmc_scene_writer_init_app(ElmcSceneWriter *writer, ElmcPebbleApp *app) {
          if (!writer) return;
          writer->app = app;
          writer->command_count = 0;
          writer->out_cmds = NULL;
          writer->max_cmds = 0;
          writer->out_count = 0;
          writer->skip_remaining = 0;
        }

        static void elmc_pebble_scene_hash_i32(ElmcPebbleApp *app, int32_t value) {
          unsigned char bytes[4];
          bytes[0] = (unsigned char)(value & 0xFF);
          bytes[1] = (unsigned char)((value >> 8) & 0xFF);
          bytes[2] = (unsigned char)((value >> 16) & 0xFF);
          bytes[3] = (unsigned char)((value >> 24) & 0xFF);
          for (int i = 0; i < 4; i++) {
            app->scene.hash ^= (uint64_t)bytes[i];
            app->scene.hash *= 1099511628211ULL;
          }
        }

        static void elmc_pebble_scene_hash_draw_cmd(ElmcPebbleApp *app, const ElmcPebbleDrawCmd *cmd) {
          if (!app || !cmd) return;
          elmc_pebble_scene_hash_i32(app, cmd->kind);
          elmc_pebble_scene_hash_i32(app, cmd->p0);
          elmc_pebble_scene_hash_i32(app, cmd->p1);
          elmc_pebble_scene_hash_i32(app, cmd->p2);
          elmc_pebble_scene_hash_i32(app, cmd->p3);
          elmc_pebble_scene_hash_i32(app, cmd->p4);
          elmc_pebble_scene_hash_i32(app, cmd->p5);
        }

        void elmc_scene_writer_init_stream(
            ElmcSceneWriter *writer,
            ElmcPebbleApp *app,
            ElmcPebbleDrawCmd *out_cmds,
            int max_cmds,
            int skip) {
          elmc_scene_writer_init_app(writer, app);
          if (!writer || !app) return;
          writer->out_cmds = out_cmds;
          writer->max_cmds = max_cmds > 0 ? max_cmds : 0;
          writer->out_count = 0;
          writer->skip_remaining = skip > 0 ? skip : 0;
          app->scene.command_count = 0;
          app->scene.hash = 1469598103934665603ULL;
        }

    """
  end

  @spec body() :: Types.c_source()
  def body do
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

    """
  end
end
