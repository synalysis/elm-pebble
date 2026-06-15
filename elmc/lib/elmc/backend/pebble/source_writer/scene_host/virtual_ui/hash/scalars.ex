defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Hash.Scalars do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        case ELMC_TAG_INT:
        case ELMC_TAG_BOOL: {
          uint64_t raw = (uint64_t)elmc_as_int(value);
          h ^= raw;
          h *= 1099511628211ULL;
          return h;
        }
    """
  end
end
