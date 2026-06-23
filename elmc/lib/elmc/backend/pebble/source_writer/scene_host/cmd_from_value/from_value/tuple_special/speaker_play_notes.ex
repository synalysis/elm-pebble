defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.FromValue.TupleSpecial.SpeakerPlayNotes do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES
        if (out_cmd->kind == ELMC_PEBBLE_CMD_SPEAKER_PLAY_NOTES &&
            tuple->second->tag == ELMC_TAG_TUPLE2 &&
            tuple->second->payload != NULL) {
          ElmcTuple2 *payload_tuple = (ElmcTuple2 *)tuple->second->payload;
          if (!payload_tuple->first || !payload_tuple->second) return -3;
          out_cmd->p0 = elmc_as_int(payload_tuple->first);
          int32_t count = 0;
          if (elmc_serialize_speaker_notes(payload_tuple->second, out_cmd->text, sizeof(out_cmd->text), &count) != 0) return -5;
          out_cmd->p1 = count;
          return 0;
        }
    #endif

    """
  end
end
