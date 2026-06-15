defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.SceneBuffer do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    typedef struct {
      unsigned char *bytes;
      int byte_count;
      int byte_capacity;
      int command_count;
      uint64_t hash;
      int dirty;
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
      struct ElmcPebbleSceneChunk *chunks;
    #endif
    } ElmcPebbleSceneBuffer;

    """
  end
end
