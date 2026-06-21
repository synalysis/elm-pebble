defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.WindowDrawEmit.ContextGroup do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
            if (tuple->first && tuple->second && elmc_as_int(tuple->first) == ELMC_PEBBLE_DRAW_CONTEXT_GROUP) {
              if (tuple->second->tag != ELMC_TAG_TUPLE2 || tuple->second->payload == NULL) return -3;
              ElmcTuple2 *ctx = (ElmcTuple2 *)tuple->second->payload;
              if (!ctx->first || !ctx->second) return -4;

              ElmcPebbleDrawCmd push_cmd;
              elmc_draw_cmd_init(&push_cmd, ELMC_PEBBLE_DRAW_PUSH_CONTEXT);
              elmc_emit_draw_cmd(&push_cmd, out_cmds, max_cmds, count, emitted, skip);
              if (*count >= max_cmds) return 0;

              ElmcValue *setting_cursor = ctx->first;
              while (setting_cursor && setting_cursor->tag == ELMC_TAG_LIST && setting_cursor->payload != NULL) {
                ElmcCons *node = (ElmcCons *)setting_cursor->payload;
                ElmcPebbleDrawCmd setting_cmd;
                if (elmc_draw_setting_cmd_from_value(node->head, &setting_cmd) == 0) {
                  elmc_emit_draw_cmd(&setting_cmd, out_cmds, max_cmds, count, emitted, skip);
                  if (*count >= max_cmds) return 0;
                }
                setting_cursor = node->tail;
              }

              ElmcValue *cmd_cursor = ctx->second;
              while (cmd_cursor && cmd_cursor->tag == ELMC_TAG_LIST && cmd_cursor->payload != NULL) {
                ElmcCons *node = (ElmcCons *)cmd_cursor->payload;
                elmc_append_draw_cmd_from_value_window(node->head, out_cmds, max_cmds, count, emitted, skip, depth + 1);
                if (*count >= max_cmds) return 0;
                cmd_cursor = node->tail;
              }

              ElmcPebbleDrawCmd pop_cmd;
              elmc_draw_cmd_init(&pop_cmd, ELMC_PEBBLE_DRAW_POP_CONTEXT);
              elmc_emit_draw_cmd(&pop_cmd, out_cmds, max_cmds, count, emitted, skip);
              return 0;
            }
          }

          ElmcPebbleDrawCmd cmd;
    """
  end
end
