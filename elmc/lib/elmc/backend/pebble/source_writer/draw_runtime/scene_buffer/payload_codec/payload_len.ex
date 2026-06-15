defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.PayloadLen.{
    KindSwitch,
    Preamble
  }

  @spec body() :: Types.c_source()
  def body do
    [
      """
      static int elmc_pebble_scene_payload_len(const ElmcPebbleDrawCmd *cmd) {
      """,
      Preamble.body(),
      KindSwitch.body()
    ]
    |> IO.iodata_to_binary()
  end
end
