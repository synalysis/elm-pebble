defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.{
    BitmapSequenceInstances,
    CmdValue,
    SceneBuffer,
    SequenceHelpers,
    VectorSequenceInstances
  }

  @spec body() :: Types.c_source()
  def body do
    [
      CmdValue.body(),
      SceneBuffer.body(),
      SequenceHelpers.body(),
      VectorSequenceInstances.body(),
      BitmapSequenceInstances.body()
    ]
    |> IO.iodata_to_binary()
  end
end
