defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.ContextSettings do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.ContextSettings.{
    ColorClearGroup,
    ContextPushPop,
    PixelOpen,
    StrokeGroup,
    SwitchOpen
  }

  @spec body() :: Types.c_source()
  def body do
    [
      SwitchOpen.body(),
      ContextPushPop.body(),
      StrokeGroup.body(),
      ColorClearGroup.body(),
      PixelOpen.body()
    ]
    |> IO.iodata_to_binary()
  end
end
