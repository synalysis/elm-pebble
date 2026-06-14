defmodule Elmc.Backend.Pebble.SceneWriter.Encode.WriterPush do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
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
