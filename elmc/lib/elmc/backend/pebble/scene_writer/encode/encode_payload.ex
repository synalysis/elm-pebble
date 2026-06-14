defmodule Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SceneWriter.Encode.EncodePayload.{Fallbacks, SwitchCases}

  @spec body() :: Types.c_source()
  def body do
    [
      """
          static int elmc_scene_writer_encode_payload(
              ElmcSceneWriter *writer,
              const ElmcPebbleDrawCmd *cmd,
              int payload_len) {
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
