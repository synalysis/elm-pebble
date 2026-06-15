defmodule Elmc.Backend.Pebble.SceneWriter.Encode do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types
  alias Elmc.Backend.Pebble.SceneWriter.Encode.{EncodePayload, Helpers, WriterPush}

  @spec body() :: Types.c_source()
  def body do
    [Helpers.body(), EncodePayload.body(), WriterPush.body()]
    |> IO.iodata_to_binary()
  end
end
