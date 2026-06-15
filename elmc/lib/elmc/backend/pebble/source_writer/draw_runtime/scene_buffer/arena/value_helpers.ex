defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ValueHelpers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.Arena.ValueHelpers.{
    FitChecks,
    ScalarRead,
    TextAndPath
  }

  @spec body() :: Types.c_source()
  def body do
    [ScalarRead.body(), FitChecks.body(), TextAndPath.body()]
    |> IO.iodata_to_binary()
  end
end
