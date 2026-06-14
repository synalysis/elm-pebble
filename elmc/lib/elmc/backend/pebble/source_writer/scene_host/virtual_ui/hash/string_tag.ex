defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Hash.StringTag do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        case ELMC_TAG_STRING: {
          const unsigned char *s = (const unsigned char *)value->payload;
          if (!s) return h;
          while (*s) {
            h ^= (uint64_t)(*s++);
            h *= 1099511628211ULL;
          }
          return h;
        }
    """
  end
end
