defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.PathPayload.Preamble do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_PATH
    static int elmc_decode_path_payload(ElmcValue *payload, ElmcPebbleDrawCmd *out_cmd) {
          if (!payload || !out_cmd) return -1;
          if (payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) return -2;
          ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
          if (!outer->first || !outer->second) return -3;

          ElmcValue *points = outer->first;
          ElmcValue *offset_and_rotation = outer->second;

          if (!offset_and_rotation || offset_and_rotation->tag != ELMC_TAG_TUPLE2 || offset_and_rotation->payload == NULL) return -4;
          ElmcTuple2 *off1 = (ElmcTuple2 *)offset_and_rotation->payload;
          if (!off1->first || !off1->second) return -5;

    """
  end
end
