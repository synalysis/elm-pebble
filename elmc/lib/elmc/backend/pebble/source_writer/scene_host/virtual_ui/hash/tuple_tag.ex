defmodule Elmc.Backend.Pebble.SourceWriter.SceneHost.VirtualUi.Hash.TupleTag do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        case ELMC_TAG_TUPLE2: {
          if (!value->payload) return h;
          ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
          h ^= elmc_hash_value(tuple->first, depth + 1);
          h *= 1099511628211ULL;
          h ^= elmc_hash_value(tuple->second, depth + 1);
          h *= 1099511628211ULL;
          return h;
        }
        default:
          return h;
    """
  end
end
