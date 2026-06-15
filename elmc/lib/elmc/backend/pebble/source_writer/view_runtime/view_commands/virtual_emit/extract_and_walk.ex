defmodule Elmc.Backend.Pebble.SourceWriter.ViewRuntime.ViewCommands.VirtualEmit.ExtractAndWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
        ElmcValue *ops = result;
        int64_t window_id = 0;
        int64_t layer_id = 0;
        int extracted = elmc_extract_virtual_canvas_ops(result, &window_id, &layer_id, &ops);
        // #region agent log
        elmc_agent_scene_probe(extracted == 0 ? 0xED996300 : 0xED9963F0);
        elmc_agent_scene_probe(0xED997000 | (uint32_t)((extracted < 0 ? -extracted : extracted) & 0xFF));
        // #endregion
        if (extracted != 0 || !ops) {
          ops = result;
        }

        // #region agent log
        if (!ops) {
          elmc_agent_scene_probe(0xED996413);
        } else if (ops->tag == ELMC_TAG_LIST) {
          elmc_agent_scene_probe(ops->payload == NULL ? 0xED996410 : 0xED996411);
        } else if (ops->tag == ELMC_TAG_TUPLE2) {
          elmc_agent_scene_probe(0xED996412);
        } else {
          elmc_agent_scene_probe(0xED996413);
        }
        // #endregion

        int emitted = 0;
        if (ops->tag == ELMC_TAG_LIST) {
          ElmcValue *cursor = ops;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < max_cmds) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            elmc_append_draw_cmd_from_value_window(node->head, out_cmds, max_cmds, &count, &emitted, skip, 0);
            cursor = node->tail;
          }
        } else {
          elmc_append_draw_cmd_from_value_window(ops, out_cmds, max_cmds, &count, &emitted, skip, 0);
        }
        if (out_emitted_end) *out_emitted_end = emitted;
    """
  end
end
