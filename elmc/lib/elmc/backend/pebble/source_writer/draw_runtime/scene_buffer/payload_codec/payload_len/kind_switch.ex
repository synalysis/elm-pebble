defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.KindSwitch.{
    ContextSettings,
    DefaultCase,
    GeometryKinds,
    TextKinds
  }

  @spec body() :: Types.c_source()
  def body do
    [ContextSettings.body(), GeometryKinds.body(), TextKinds.body(), DefaultCase.body()]
    |> IO.iodata_to_binary()
  end
end
