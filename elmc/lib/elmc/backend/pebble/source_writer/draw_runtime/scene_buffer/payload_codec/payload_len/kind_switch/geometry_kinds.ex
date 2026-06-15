defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.GeometryKinds do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.GeometryKinds.{
    Circle,
    LineRect,
    Pixel,
    RoundRect,
    TextOpen
  }

  @spec body() :: Types.c_source()
  def body do
    [Pixel.body(), LineRect.body(), Circle.body(), RoundRect.body(), TextOpen.body()]
    |> IO.iodata_to_binary()
  end
end
