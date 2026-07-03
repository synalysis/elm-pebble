defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.UnpackPayload do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    static int elmc_unpack_draw_payload(ElmcValue *payload, int64_t out[6]) {
          if (!payload) return -1;
          ElmcValue *current = payload;
          for (int i = 0; i < 5; i++) {
            if (!current || current->tag != ELMC_TAG_TUPLE2 || current->payload == NULL) return -2;
            ElmcTuple2 *tuple = (ElmcTuple2 *)current->payload;
            if (!tuple->first || !tuple->second) return -3;
            out[i] = elmc_as_int(tuple->first);
            current = tuple->second;
          }
          if (!current || current->tag != ELMC_TAG_TUPLE2 || current->payload == NULL) return -4;
          {
            ElmcTuple2 *tail = (ElmcTuple2 *)current->payload;
            if (!tail->first) return -5;
            out[5] = elmc_as_int(tail->first);
          }
          return 0;
        }

"""
  end
end
