defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.FromValue.TupleDefault do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
            if (elmc_unpack_draw_payload(tuple->second, payload) == 0) {
              out_cmd->p0 = payload[0];
              out_cmd->p1 = payload[1];
              out_cmd->p2 = payload[2];
              out_cmd->p3 = payload[3];
              out_cmd->p4 = payload[4];
              out_cmd->p5 = payload[5];
            } else {
              out_cmd->p0 = elmc_as_int(tuple->second);
            }
            return 0;
          }

          return -4;
        }
"""
  end
end
