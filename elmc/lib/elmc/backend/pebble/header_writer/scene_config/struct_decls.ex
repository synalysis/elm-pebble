defmodule Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.HeaderWriter.SceneConfig.StructDecls.{
    AppStruct,
    Rect,
    SceneBuffer,
    SceneChunk
  }

  @spec body() :: Types.c_source()
  def body do
    [SceneBuffer.body(), SceneChunk.body(), Rect.body(), AppStruct.body()]
    |> IO.iodata_to_binary()
  end
end
