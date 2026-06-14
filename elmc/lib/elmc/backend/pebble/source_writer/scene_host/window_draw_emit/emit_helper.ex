defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.WindowDrawEmit.EmitHelper do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if !defined(ELMC_PEBBLE_DIRECT_VIEW_SCENE)
    static void elmc_emit_draw_cmd(
        const ElmcPebbleDrawCmd *cmd,
        ElmcPebbleDrawCmd *out_cmds,
        int max_cmds,
        int *count,
        int *emitted,
        int skip) {
      if (!cmd || !out_cmds || !count || !emitted) return;
      if (*emitted >= skip && *count < max_cmds) {
        out_cmds[*count] = *cmd;
        *count += 1;
      }
      *emitted += 1;
    }

    static int elmc_append_draw_cmd_from_value_window(
        ElmcValue *value,
        ElmcPebbleDrawCmd *out_cmds,
        int max_cmds,
        int *count,
        int *emitted,
        int skip,
        int depth) {
      if (!value || !out_cmds || !count || !emitted) return -1;
      if (depth > 32) return -2;
      if (*count >= max_cmds) return 0;

      if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
        ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
"""
  end
end
