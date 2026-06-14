defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.CmdPayload do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
      if (value->tag == ELMC_TAG_CMD && value->payload != NULL) {
        ElmcCmdPayload *cmd = (ElmcCmdPayload *)value->payload;
        out_cmd->kind = cmd->kind;
        if (cmd->arity > 0) out_cmd->p0 = cmd->p0;
        if (cmd->arity > 1) out_cmd->p1 = cmd->p1;
        if (cmd->arity > 2) out_cmd->p2 = cmd->p2;
        if (cmd->arity > 3) out_cmd->p3 = cmd->p3;
        if (cmd->arity > 4) out_cmd->p4 = cmd->p4;
        if (cmd->arity > 5) out_cmd->p5 = cmd->p5;
        if (cmd->text && cmd->text->tag == ELMC_TAG_STRING && cmd->text->payload) {
          strncpy(out_cmd->text, (const char *)cmd->text->payload, sizeof(out_cmd->text) - 1);
          out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
        }
        return 0;
      }

"""
  end
end
