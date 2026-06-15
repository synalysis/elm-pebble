defmodule Elmc.Backend.Pebble.SceneWriter.Encode.Helpers.WriterPut do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

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
