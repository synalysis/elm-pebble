defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.PathPayload do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.PathPayload.{
    Epilogue,
    OffsetRotation,
    PointsLoop,
    Preamble
  }

  @spec body() :: Types.c_source()
  def body do
    [Preamble.body(), OffsetRotation.body(), PointsLoop.body(), Epilogue.body()]
    |> IO.iodata_to_binary()
  end
end
