defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.CmdFromValue.SerializeList do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_CMD_VIBES_CUSTOM_PATTERN || ELMC_PEBBLE_FEATURE_CMD_DATA_LOG_BYTES
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
      ElmcValue *cursor = value;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!node->head) break;
        int64_t item = elmc_as_int(node->head);
        char chunk[24];
        int n = snprintf(
            chunk,
            sizeof(chunk),
            (*out_count == 0) ? "%ld" : ",%ld",
            (long)item);
        if (n <= 0 || used + (size_t)n >= out_size) return -2;
        strncat(out_text, chunk, out_size - used - 1);
        used += (size_t)n;
        *out_count += 1;
        cursor = node->tail;
        if (*out_count >= 64) break;
      }
      return 0;
    }
    #endif

"""
  end
end
