defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.PathPayload.PointsLoop do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          int count = 0;
          ElmcValue *cursor = points;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < 16) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            if (!node->head || node->head->tag != ELMC_TAG_TUPLE2 || node->head->payload == NULL) break;
            ElmcTuple2 *point = (ElmcTuple2 *)node->head->payload;
            if (!point->first || !point->second) break;
            out_cmd->path_x[count] = elmc_as_int(point->first);
            out_cmd->path_y[count] = elmc_as_int(point->second);
            count += 1;
            cursor = node->tail;
          }
          out_cmd->path_point_count = count;
          return count > 0 ? 0 : -8;
        }
    """
  end
end
