defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Hash.ListTag do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        case ELMC_TAG_LIST: {
          ElmcValue *cursor = value;
          int count = 0;
          while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL && count < 128) {
            ElmcCons *node = (ElmcCons *)cursor->payload;
            uint64_t head_h = elmc_hash_value(node->head, depth + 1);
            h ^= head_h;
            h *= 1099511628211ULL;
            cursor = node->tail;
            count += 1;
          }
          return h;
        }
    """
  end
end
