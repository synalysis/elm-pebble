defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.Rect do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    typedef struct {
      int x;
      int y;
      int w;
      int h;
    } ElmcPebbleRect;

    """
  end
end
