defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.TextCopy.CopyDrawText.ListWalk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
          size_t used = 0;
          ElmcValue *cursor = value;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            const char *piece = NULL;
            char char_buf[2] = {0, 0};
            if (!node->head) {
              cursor = node->tail;
              continue;
            }
            if (node->head->tag == ELMC_TAG_STRING && node->head->payload != NULL) {
              piece = (const char *)node->head->payload;
            } else {
              char_buf[0] = (char)elmc_as_int(node->head);
              piece = char_buf;
            }
            size_t piece_len = strlen(piece);
            if (piece_len == 0) {
              cursor = node->tail;
              continue;
            }
            if (used + piece_len >= out_size) {
              size_t copy_len = out_size - used - 1;
              if (copy_len > 0) {
                memcpy(out_text + used, piece, copy_len);
                used += copy_len;
              }
              break;
            }
            memcpy(out_text + used, piece, piece_len);
            used += piece_len;
            cursor = node->tail;
          }
          out_text[used] = '\\0';
          return used > 0 ? 0 : -1;
        }
        #endif
"""
  end
end
