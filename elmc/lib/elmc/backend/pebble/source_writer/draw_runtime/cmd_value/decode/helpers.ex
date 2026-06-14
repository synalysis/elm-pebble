defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.Helpers.{
    TextCopy,
    UnpackPayload
  }

  @spec body() :: Types.c_source()
  def body do
    [UnpackPayload.body(), TextCopy.body()]
    |> IO.iodata_to_binary()
  end
end
