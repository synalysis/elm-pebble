defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.FromValue.TupleText do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
            if (out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT ||
                out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT_LABEL_WITH_FONT) {
              int text_payload_count = out_cmd->kind == ELMC_PEBBLE_DRAW_TEXT ? 6 : 5;
              int64_t payload[6] = {0, 0, 0, 0, 0, 0};
              ElmcValue *current = tuple->second;
              for (int i = 0; i < text_payload_count; i++) {
                if (!current || current->tag != ELMC_TAG_TUPLE2 || current->payload == NULL) return -5;
                ElmcTuple2 *node = (ElmcTuple2 *)current->payload;
                if (!node->first || !node->second) return -6;
                payload[i] = elmc_as_int(node->first);
                current = node->second;
              }
              out_cmd->p0 = payload[0];
              out_cmd->p1 = payload[1];
              out_cmd->p2 = payload[2];
              out_cmd->p3 = payload[3];
              out_cmd->p4 = payload[4];
              out_cmd->p5 = payload[5];
              (void)elmc_copy_draw_text_value(current, out_cmd->text, sizeof(out_cmd->text));
              return 0;
            }
        #endif
            int64_t payload[6] = {0, 0, 0, 0, 0, 0};
"""
  end
end
