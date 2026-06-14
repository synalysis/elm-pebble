defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.PathPayload.OffsetRotation do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          if (off1->first->tag == ELMC_TAG_TUPLE2 && off1->first->payload != NULL) {
            /* Pebble.Ui.path: tuple2(points, tuple2(tuple2(offset_x, offset_y), rotation)) */
            ElmcTuple2 *xy = (ElmcTuple2 *)off1->first->payload;
            if (!xy->first || !xy->second) return -6;
            out_cmd->path_offset_x = elmc_as_int(xy->first);
            out_cmd->path_offset_y = elmc_as_int(xy->second);
            out_cmd->path_rotation = elmc_as_int(off1->second);
          } else {
            /* path_expr: tuple2(points, tuple2(offset_x, tuple2(offset_y, rotation))) */
            out_cmd->path_offset_x = elmc_as_int(off1->first);

            if (off1->second->tag != ELMC_TAG_TUPLE2 || off1->second->payload == NULL) return -6;
            ElmcTuple2 *off2 = (ElmcTuple2 *)off1->second->payload;
            if (!off2->first || !off2->second) return -7;
            out_cmd->path_offset_y = elmc_as_int(off2->first);
            out_cmd->path_rotation = elmc_as_int(off2->second);
          }

    """
  end
end
