defmodule Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  alias Elmc.Backend.Pebble.SourceWriter.DrawRuntime.CmdValue.Decode.PathSettings.{
    DrawSettings,
    MainViewClose,
    PathPayload
  }

  @spec body() :: Types.c_source()
  def body do
    [PathPayload.body(), DrawSettings.body(), MainViewClose.body()]
    |> IO.iodata_to_binary()
  end
end
