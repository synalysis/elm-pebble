defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Chunks do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.Chunks.{
    ChunkAppend,
    ChunkTail,
    ChunksFree,
    Epilogue,
    Materialize,
    Preamble
  }

  @spec body() :: Types.c_source()
  def body do
    [
      Preamble.body(),
      ChunksFree.body(),
      ChunkTail.body(),
      ChunkAppend.body(),
      Materialize.body(),
      Epilogue.body()
    ]
    |> IO.iodata_to_binary()
  end
end
