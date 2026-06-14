defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.DrawSettings.ResetFields do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        static int elmc_draw_setting_cmd_from_value(ElmcValue *value, ElmcPebbleDrawCmd *out_cmd) {
          if (!out_cmd || !value || value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return -1;
          ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
          if (!tuple->first || !tuple->second) return -2;

          int64_t setting_tag = elmc_as_int(tuple->first);
          int64_t setting_value = elmc_as_int(tuple->second);

          out_cmd->kind = ELMC_PEBBLE_DRAW_NONE;
          out_cmd->p0 = setting_value;
          out_cmd->p1 = 0;
          out_cmd->p2 = 0;
          out_cmd->p3 = 0;
          out_cmd->p4 = 0;
          out_cmd->p5 = 0;
        #if ELMC_PEBBLE_FEATURE_DRAW_PATH
          out_cmd->path_point_count = 0;
          out_cmd->path_offset_x = 0;
          out_cmd->path_offset_y = 0;
          out_cmd->path_rotation = 0;
          for (int i = 0; i < 16; i++) {
            out_cmd->path_x[i] = 0;
            out_cmd->path_y[i] = 0;
          }
        #endif
          out_cmd->text[0] = '\0';

    """
  end
end
