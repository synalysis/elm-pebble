defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.Prologue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_cmd_from_value(ElmcValue *value, ElmcPebbleCmd *out_cmd) {
      if (!out_cmd) return -1;
      out_cmd->kind = ELMC_PEBBLE_CMD_NONE;
      out_cmd->p0 = 0;
      out_cmd->p1 = 0;
      out_cmd->p2 = 0;
      out_cmd->p3 = 0;
      out_cmd->p4 = 0;
      out_cmd->p5 = 0;
      out_cmd->text[0] = '\\0';
      if (!value) return -2;

      if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
        out_cmd->kind = elmc_as_int(value);
        return 0;
      }

"""
  end
end
