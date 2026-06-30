defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.SerializeList do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN || ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_STREAM_WRITE
    static int elmc_serialize_append_int(
        char *out_text,
        size_t out_size,
        size_t *used,
        int32_t *out_count,
        int64_t item) {
      if (!out_text || !used || !out_count) return -1;
      char chunk[24];
      int n = snprintf(
          chunk,
          sizeof(chunk),
          (*out_count == 0) ? "%ld" : ",%ld",
          (long)item);
      if (n <= 0 || *used + (size_t)n >= out_size) return -2;
      strncat(out_text, chunk, out_size - *used - 1);
      *used += (size_t)n;
      *out_count += 1;
      return 0;
    }

    static int elmc_serialize_int_list(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      if (value->tag == ELMC_TAG_INT_LIST) {
        ElmcIntListPayload *payload =
            (value->payload != NULL) ? (ElmcIntListPayload *)value->payload : NULL;
        if (!payload) return 0;
        for (int i = 0; i < payload->length; i++) {
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, payload->values[i]) != 0) {
            return -2;
          }
          if (*out_count >= 64) break;
        }
        return 0;
      }
      if (value->tag == ELMC_TAG_INT_SPINE) {
        ElmcValue *cursor = value;
        while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count,
                                        ((ElmcIntSpine *)cursor->payload)->head) != 0) {
            return -2;
          }
          cursor = ((ElmcIntSpine *)cursor->payload)->tail;
          if (*out_count >= 64) break;
        }
        return 0;
      }
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;
        if (elmc_serialize_append_int(out_text, out_size, &used, out_count, elmc_as_int(node->head)) != 0) {
          return -2;
        }
        cursor = node->tail;
        if (*out_count >= 64) break;
      }
      return 0;
    }
    #endif

    #if ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_NOTES || ELMC_PEBBLE_FEATURE_CMD_SPEAKER_PLAY_TRACKS
    static int elmc_serialize_speaker_note_record(
        ElmcValue *note,
        char *out_text,
        size_t out_size,
        size_t *used,
        int32_t *out_count) {
      if (!note || note->tag != ELMC_TAG_RECORD || !note->payload) return -3;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "midiNote")) != 0) return -2;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "waveform")) != 0) return -2;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "durationMs")) != 0) return -2;
      if (elmc_serialize_append_int(out_text, out_size, used, out_count,
                                    elmc_record_get_int(note, "velocity")) != 0) return -2;
      return 0;
    }

    static int elmc_serialize_speaker_notes(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;
        if (node->head->tag == ELMC_TAG_RECORD) {
          if (elmc_serialize_speaker_note_record(node->head, out_text, out_size, &used, out_count) != 0) return -2;
        } else if (node->head->tag == ELMC_TAG_INT || node->head->tag == ELMC_TAG_BOOL) {
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, elmc_as_int(node->head)) != 0) return -2;
        } else {
          return -3;
        }
        cursor = node->tail;
        if (*out_count >= 64) break;
      }
      return 0;
    }

    static int32_t elmc_speaker_sample_index_from_maybe(ElmcValue *maybe_sample) {
      ElmcValue *sample = elmc_maybe_or_tuple_just_payload_borrow(maybe_sample);
      if (!sample) return 0;
      if (sample->tag == ELMC_TAG_INT || sample->tag == ELMC_TAG_BOOL) {
        int32_t slot = (int32_t)elmc_as_int(sample);
        return slot > 0 ? slot : 0;
      }
      return 0;
    }

    static int elmc_serialize_speaker_tracks(
        ElmcValue *value,
        char *out_text,
        size_t out_size,
        int32_t *out_count) {
      if (!out_text || out_size == 0 || !out_count) return -1;
      out_text[0] = '\\0';
      *out_count = 0;
      if (!value) return 0;

      size_t used = 0;
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;

        if (node->head->tag == ELMC_TAG_RECORD && node->head->payload) {
          ElmcValue *notes = elmc_record_get(node->head, "notes");
          ElmcValue *sample = elmc_record_get(node->head, "sample");
          int32_t note_count = 0;
          ElmcValue *note_cursor = notes;
          while (note_cursor && note_cursor->tag == ELMC_TAG_LIST && note_cursor->payload != NULL) {
            ElmcCons *note_node = (ElmcCons *)note_cursor->payload;
            if (!note_node->head) break;
            note_count++;
            note_cursor = note_node->tail;
            if (note_count > 256) break;
          }
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, note_count) != 0) return -2;
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count,
                                        elmc_speaker_sample_index_from_maybe(sample)) != 0) return -2;
          note_cursor = notes;
          int32_t serialized_notes = 0;
          while (note_cursor && note_cursor->tag == ELMC_TAG_LIST && note_cursor->payload != NULL) {
            ElmcCons *note_node = (ElmcCons *)note_cursor->payload;
            if (!note_node->head) break;
            if (elmc_serialize_speaker_note_record(note_node->head, out_text, out_size, &used, out_count) != 0) {
              return -2;
            }
            serialized_notes++;
            note_cursor = note_node->tail;
            if (serialized_notes >= note_count || *out_count >= 64) break;
          }
        } else if (node->head->tag == ELMC_TAG_INT || node->head->tag == ELMC_TAG_BOOL) {
          if (elmc_serialize_append_int(out_text, out_size, &used, out_count, elmc_as_int(node->head)) != 0) {
            return -2;
          }
        } else {
          return -3;
        }

        cursor = node->tail;
        if (*out_count >= 64) break;
      }
      return 0;
    }
    #endif

"""
  end
end
