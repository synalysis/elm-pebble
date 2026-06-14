defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.SceneChunk do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_SCENE_CHUNK_SIZE > 0
    typedef struct ElmcPebbleSceneChunk {
      struct ElmcPebbleSceneChunk *next;
      int used;
      unsigned char bytes[ELMC_PEBBLE_SCENE_CHUNK_SIZE];
    } ElmcPebbleSceneChunk;
    #endif

    """
  end
end
