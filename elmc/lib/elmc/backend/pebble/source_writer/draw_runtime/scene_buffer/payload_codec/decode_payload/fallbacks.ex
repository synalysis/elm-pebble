defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.Fallbacks do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.Fallbacks.{
    PathFull,
    TextDraw,
    TextLabel,
    TextTail
  }

  @spec body() :: Types.c_source()
  def body do
    [TextDraw.body(), TextLabel.body(), PathFull.body(), TextTail.body()]
    |> IO.iodata_to_binary()
  end
end
