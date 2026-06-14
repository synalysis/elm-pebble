defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial.StorageWriteString do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        if (out_cmd->kind == ELMC_PEBBLE_CMD_STORAGE_WRITE_STRING &&
            tuple->second->tag == ELMC_TAG_TUPLE2 &&
            tuple->second->payload != NULL) {
          ElmcTuple2 *payload_tuple = (ElmcTuple2 *)tuple->second->payload;
          if (!payload_tuple->first || !payload_tuple->second) return -3;
          out_cmd->p0 = elmc_as_int(payload_tuple->first);
          ElmcValue *text_value = payload_tuple->second;
          while (text_value && text_value->tag == ELMC_TAG_TUPLE2 && text_value->payload != NULL) {
            ElmcTuple2 *nested = (ElmcTuple2 *)text_value->payload;
            text_value = nested->first;
          }
          if (text_value && text_value->tag == ELMC_TAG_STRING && text_value->payload) {
            strncpy(out_cmd->text, (const char *)text_value->payload, sizeof(out_cmd->text) - 1);
            out_cmd->text[sizeof(out_cmd->text) - 1] = '\\0';
          }
          return 0;
        }

    """
  end
end
