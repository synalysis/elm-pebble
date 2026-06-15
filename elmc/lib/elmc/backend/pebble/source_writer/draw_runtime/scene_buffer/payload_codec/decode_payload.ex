defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.SceneBuffer.PayloadCodec.DecodePayload.{
    Fallbacks,
    SwitchCases
  }

  @spec body() :: Types.c_source()
  def body do
    [
      """
      static int elmc_pebble_scene_decode_payload(
          int kind,
          int payload_len,
          const unsigned char *bytes,
          int *offset,
          int payload_end,
          ElmcPebbleDrawCmd *out_cmd) {
      """,
      SwitchCases.body(),
      Fallbacks.body(),
      """
        return -4;
      }
      """
    ]
    |> IO.iodata_to_binary()
  end
end
