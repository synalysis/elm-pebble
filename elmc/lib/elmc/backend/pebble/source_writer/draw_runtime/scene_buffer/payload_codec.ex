defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.{DecodePayload, PayloadLen, ReadHelpers}

  @spec body() :: Types.c_source()
  def body do
    [PayloadLen.body(), ReadHelpers.body(), DecodePayload.body()]
    |> IO.iodata_to_binary()
  end
end
