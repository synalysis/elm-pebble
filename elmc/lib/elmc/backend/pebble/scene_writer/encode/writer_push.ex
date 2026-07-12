defmodule Elmc.Backend.Pebble.SceneWriter.Encode.WriterPush do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    RC elmc_scene_writer_push_cmd(ElmcSceneWriter *writer, const ElmcPebbleDrawCmd *cmd) {
          if (!writer || !writer->app || !cmd) return RC_ERR_SCENE_BUFFER_OVERFLOW;
    #if ELMC_PEBBLE_SCENE_STREAM_CMDS
          writer->command_count += 1;
          writer->app->scene.command_count = writer->command_count;
          elmc_pebble_scene_hash_draw_cmd(writer->app, cmd);
          if (writer->skip_remaining > 0) {
            writer->skip_remaining -= 1;
            return RC_SUCCESS;
          }
          if (!writer->out_cmds || writer->out_count >= writer->max_cmds) return RC_SUCCESS;
          writer->out_cmds[writer->out_count++] = *cmd;
          return RC_SUCCESS;
    #else
          int payload_len = elmc_pebble_scene_payload_len(cmd);
          if (payload_len < 0 || payload_len > 255) return RC_ERR_SCENE_BUFFER_OVERFLOW;
          int rc = elmc_scene_writer_put_u8(writer, (unsigned char)cmd->kind);
          if (rc != 0) return RC_ERR_SCENE_BUFFER_OVERFLOW;
          rc = elmc_scene_writer_put_u8(writer, (unsigned char)payload_len);
          if (rc != 0) return RC_ERR_SCENE_BUFFER_OVERFLOW;
          rc = elmc_scene_writer_encode_payload(writer, cmd, payload_len);
          if (rc != 0) return RC_ERR_SCENE_BUFFER_OVERFLOW;
          writer->command_count += 1;
          writer->app->scene.command_count = writer->command_count;
          return RC_SUCCESS;
    #endif
        }

    """
  end
end
